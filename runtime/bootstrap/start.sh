#! /bin/bash

LATEST_RUNTIME_ENV_VERSION="260101"
LATEST_RUNTIME_CODE_VERSION="260101"

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

        if [ -d /kepilot/code ]; then rm -rf /kepilot/code;

        # install_dependencies
        mkdir -p /kepilot/code && cd /kepilot/code

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

        # Copy Project source files
        if [ -d /kepilot/code/openhands ]; then rm -rf /kepilot/code/openhands; fi

        # install_vscode_extensions
        mkdir -p ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-hello-world && \
        cp -r /kepilot/code/openhands/runtime/utils/vscode-extensions/hello-world/* ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-hello-world/

        mkdir -p ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-memory-monitor && \
        cp -r /kepilot/code/openhands/runtime/utils/vscode-extensions/memory-monitor/* ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-memory-monitor/
    fi

    echo "Upgrading execution runtime from version $CURRENT_VERSION to $LATEST_RUNTIME_ENV_VERSION..."

    if [ "$CURRENT_VERSION" -lt "$FIRST_TIME_VERSION" ]; then
        apt-get install -y --no-install-recommends libgl1
        apt-get install -y fonts-unifont fonts-ubuntu || apt-get install -y ttf-unifont ttf-ubuntu-font-family
        /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install --with-deps chromium || \
            (apt-get install -y libnss3 libnspr4 libatk1.0-0 libatspi2.0-0 libxcomposite1 libxdamage1 libxrandr2 libxkbcommon0 && \
            /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install chromium)
    fi

    # write the latest version to the version file
    echo "$LATEST_RUNTIME_ENV_VERSION" > "$VERSION_FILE"
    
    set +e
}

upgrade_runtime_code() {
    set -e

    VERSION_FILE="/opt/runtime/execution_runtime_code_version.txt"
    PRIMITIVE_TIME_VERSION="251201" # the version before we introduced the version tracking

    CURRENT_VERSION=$PRIMITIVE_TIME_VERSION
    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
    fi

    if [ "$CURRENT_VERSION" -ge "$LATEST_RUNTIME_CODE_VERSION" ]; then
        echo "Execution runtime code is already up to date (version $CURRENT_VERSION). No upgrade needed."
        return
    fi

    # download the latest code package from https://raw.githubusercontent.com/nenus-ai/public-resource-hub/master/runtime/packages/runtime_execution_server.260101.tar.gz
    # unzip, the unziped folder is code/
    # remove the existing /kepilot/code/ folder
    # move the unzipped code/ folder to /kepilot/code/
    echo "Upgrading execution runtime code from version $CURRENT_VERSION to $LATEST_RUNTIME_CODE_VERSION..."
    REMOTE_URL="https://raw.githubusercontent.com/nenus-ai/public-resource-hub/master/runtime/packages/runtime_execution_server.$LATEST_RUNTIME_CODE_VERSION.tar.gz"
    # Download and extract the package into a temporary directory
    TEMP_DIR=$(mktemp -d)
    curl -L "$REMOTE_URL" -o "$TEMP_DIR/runtime_code.tar.gz"
    tar -xzf "$TEMP_DIR/runtime_code.tar.gz" -C "$TEMP_DIR"

    # Remove the existing /kepilot/code/ folder
    if [ -d /kepilot/code ]; then
        rm -rf /kepilot/code
    fi
    # Move the unzipped code/ folder to /kepilot/code/
    mv "$TEMP_DIR/code" /kepilot/code

    # cp /kepilot/code/openhands/pyproject.toml  /kepilot/code/openhands/poetry.lock /kepilot/code/
    chmod a+rwx /kepilot/code/openhands/__init__.py

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    # write the latest version to the version file
    echo "$LATEST_RUNTIME_CODE_VERSION" > "$VERSION_FILE"

    set +e
}

function upgrade() {
    set -e
    upgrade_environment
    upgrade_runtime_code
    set +e
}

start()
{
    echo "Starting execution runtime environment setup..."

    COMMAND_TO_RUNTIME="/kepilot/micromamba/bin/micromamba run -n kepilot poetry run python -u -m openhands.runtime.action_execution_server 12000 --working-dir /workspace --plugins agent_skills vscode --username kepilot --user-id 1000"

    export POETRY_VIRTUALENVS_PATH="/kepilot/poetry"
    export MAMBA_ROOT_PREFIX=/kepilot/micromamba
    export OPENVSCODE_SERVER_ROOT=/kepilot/.openvscode-server
    export PATH="/kepilot/bin:${PATH}"

    # execute the command to start the runtime environment
    echo "Starting execution runtime environment..."
    exec /bin/bash -c "$COMMAND_TO_RUNTIME"
}

# log upgrade errors and output to /kepilot/logs/bootstrap.log
{
    upgrade
} >> /opt/runtime/bootstrap.log 2>&1

start