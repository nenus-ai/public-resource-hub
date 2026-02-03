#! /bin/bash

LATEST_RUNTIME_ENV_VERSION="260101"
LATEST_RUNTIME_CODE_VERSION="260201"

upgrade_environment() {
    set -e

    echo "Upgrading execution runtime environment..."

    VERSION_FILE="/opt/runtime/execution_runtime_env_version.txt"
    OPENHANDS_TIME_VERSION="250501" # very old version from openhands
    PRIMITIVE_TIME_VERSION="251201" # the version before we introduced the version tracking
    FIRST_TIME_VERSION="260101" # the first version with version tracking

    CURRENT_VERSION=$PRIMITIVE_TIME_VERSION

    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
    else
        if [ ! -f "/kepilot/micromamba/bin/micromamba" ]; then
            CURRENT_VERSION=$OPENHANDS_TIME_VERSION
        fi
    fi

    if [ "$CURRENT_VERSION" -eq "$OPENHANDS_TIME_VERSION" ]; then
        echo "Detected very old version from openhands ($CURRENT_VERSION). Upgrading..."

        export POETRY_VIRTUALENVS_PATH="/kepilot/poetry"
        export MAMBA_ROOT_PREFIX=/kepilot/micromamba
        export OPENVSCODE_SERVER_ROOT=/kepilot/.openvscode-server

        # setup_base_system
        curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/kepilot/bin" sh
        export PATH="/kepilot/bin:${PATH}"

        mkdir -p /kepilot && \
        mkdir -p /kepilot/logs && \
        mkdir -p /kepilot/poetry

        # Install micromamba
        mkdir -p /kepilot/micromamba/bin && \
            /bin/bash -c "PREFIX_LOCATION=/kepilot/micromamba BIN_FOLDER=/kepilot/micromamba/bin INIT_YES=no CONDA_FORGE_YES=yes $(curl -L https://micro.mamba.pm/install.sh)" && \
            /kepilot/micromamba/bin/micromamba config remove channels defaults && \
            /kepilot/micromamba/bin/micromamba config list

        # Create the kepilot virtual environment and install poetry and python
        /kepilot/micromamba/bin/micromamba create -n kepilot -y && \
            /kepilot/micromamba/bin/micromamba install -n kepilot -c conda-forge poetry python=3.12 -y

        # install_dependencies
        cd /kepilot/code

        /kepilot/micromamba/bin/micromamba config set changeps1 False && \
        /kepilot/micromamba/bin/micromamba run -n kepilot poetry config virtualenvs.path /kepilot/poetry && \
        /kepilot/micromamba/bin/micromamba run -n kepilot poetry env use python3.12

        /kepilot/micromamba/bin/micromamba run -n kepilot poetry install --only main --no-interaction --no-root
        /kepilot/micromamba/bin/micromamba run -n kepilot poetry install --only runtime --no-interaction --no-root

        /kepilot/micromamba/bin/micromamba run -n kepilot poetry run pip install playwright && \
        /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install --with-deps chromium

        /kepilot/micromamba/bin/micromamba run -n kepilot poetry run python -c "import sys; print('OH_INTERPRETER_PATH=' + sys.executable)" >> /etc/environment && \
        chmod -R g+rws /kepilot/poetry && \
        mkdir -p /kepilot/workspace && chmod -R g+rws,o+rw /kepilot/workspace

        /kepilot/micromamba/bin/micromamba run -n kepilot poetry cache clear --all . -n && \
        /kepilot/micromamba/bin/micromamba clean --all

        # install_vscode_extensions
        mkdir -p ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-hello-world && \
        cp -r /kepilot/code/openhands/runtime/utils/vscode-extensions/hello-world/* ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-hello-world/

        mkdir -p ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-memory-monitor && \
        cp -r /kepilot/code/openhands/runtime/utils/vscode-extensions/memory-monitor/* ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-memory-monitor/

        echo "$PRIMITIVE_TIME_VERSION" > "$VERSION_FILE"
    fi

    echo "Upgrading execution runtime from version $CURRENT_VERSION to $LATEST_RUNTIME_ENV_VERSION..."

    if [ "$CURRENT_VERSION" -lt "$FIRST_TIME_VERSION" ]; then
        cd /kepilot/code

        apt-get update && apt-get install -y --no-install-recommends libgl1
        apt-get install -y fonts-unifont fonts-ubuntu || apt-get install -y ttf-unifont ttf-ubuntu-font-family || true
        /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install --with-deps chromium || \
            (apt-get install -y libnss3 libnspr4 libatk1.0-0 libatspi2.0-0 libxcomposite1 libxdamage1 libxrandr2 libxkbcommon0 && \
            /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install chromium)

        echo "$FIRST_TIME_VERSION" > "$VERSION_FILE"
    fi

    # write the latest version to the version file
    echo "$LATEST_RUNTIME_ENV_VERSION" > "$VERSION_FILE"
    
    set +e
}

upgrade_runtime_code() {
    set -e

    mkdir -p /kepilot/code

    VERSION_FILE="/kepilot/code/openhands/execution_runtime_code_version.txt"
    PRIMITIVE_TIME_VERSION="251201" # the version before we introduced the version tracking

    CURRENT_VERSION=$PRIMITIVE_TIME_VERSION
    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
    fi

    if [ "$CURRENT_VERSION" -ge "$LATEST_RUNTIME_CODE_VERSION" ]; then
        echo "Execution runtime code is already up to date (version $CURRENT_VERSION). No upgrade needed."
        return
    fi

    echo "Upgrading execution runtime code from version $CURRENT_VERSION to $LATEST_RUNTIME_CODE_VERSION..."
    REMOTE_URL="https://raw.githubusercontent.com/nenus-ai/public-resource-hub/master/runtime/packages/runtime_execution_server.$LATEST_RUNTIME_CODE_VERSION.tar.gz"
    # Download and extract the package into a temporary directory
    TEMP_DIR=$(mktemp -d)
    curl -L "$REMOTE_URL" -o "$TEMP_DIR/runtime_code.tar.gz"
    tar -xzf "$TEMP_DIR/runtime_code.tar.gz" -C "$TEMP_DIR"

    if [ -d /kepilot/code/openhands ]; then
        rm -rf /kepilot/code/openhands
    fi

    mv "$TEMP_DIR/code/openhands" /kepilot/code/openhands
    mv "$TEMP_DIR/code/poetry.lock" /kepilot/code/poetry.lock
    mv "$TEMP_DIR/code/pyproject.toml" /kepilot/code/pyproject.toml

    chmod a+rwx /kepilot/code/openhands/__init__.py

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    # write the latest version to the version file
    echo "$LATEST_RUNTIME_CODE_VERSION" > "$VERSION_FILE"

    set +e
}

function upgrade() {
    set -e
    upgrade_runtime_code
    upgrade_environment
    set +e
}

start()
{
    echo "*******************************************************************************************************"
    echo "*********************Starting execution runtime environment at $(date +"%Y-%m-%d %T")*********************"

    COMMAND_TO_RUNTIME="/kepilot/micromamba/bin/micromamba run -n kepilot poetry run python -u -m openhands.runtime.action_execution_server 12000 --working-dir /workspace --plugins agent_skills vscode --user-id 1000"

    export POETRY_VIRTUALENVS_PATH="/kepilot/poetry"
    export MAMBA_ROOT_PREFIX=/kepilot/micromamba
    export OPENVSCODE_SERVER_ROOT=/kepilot/.openvscode-server
    export PATH="/kepilot/bin:${PATH}"

    # execute the command to start the runtime environment
    echo "Starting execution runtime environment..."
    exec /bin/bash -c "$COMMAND_TO_RUNTIME"
}

{
    echo "======================================================================"
    echo "================Start upgrades at $(date +"%Y-%m-%d %T")================="

    upgrade

    echo "================Upgrades completed at $(date +"%Y-%m-%d %T")================"
    echo "======================================================================"
} 2>&1 | tee -a /opt/runtime/bootstrap.log

start
