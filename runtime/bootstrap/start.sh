#! /bin/bash

COMMAND_TO_RUNTIME="/kepilot/micromamba/bin/micromamba run -n kepilot poetry run python -u -m openhands.runtime.action_execution_server 12000 --working-dir /workspace --plugins agent_skills vscode --username kepilot --user-id 1000"

export POETRY_VIRTUALENVS_PATH="/kepilot/poetry"
export MAMBA_ROOT_PREFIX=/kepilot/micromamba
export OPENVSCODE_SERVER_ROOT=/kepilot/.openvscode-server
export PATH="/kepilot/bin:${PATH}"

# execute the command to start the runtime environment
echo "Starting execution runtime environment..."
exec /bin/bash -c "$COMMAND_TO_RUNTIME"