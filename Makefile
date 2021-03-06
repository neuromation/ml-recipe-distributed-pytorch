##### PATHS #####

VERSION=v1.3
PROJECT_ID=neuro-project-2c0e9469

DATA_DIR?=data
CONFIG_DIR?=config
CODE_DIR?=modules
NOTEBOOKS_DIR?=notebooks
RESULTS_DIR?=results
SCRIPTS_DIR?=scripts

PROJECT_FILES=requirements.txt apt.txt setup.cfg project_configure.sh

PROJECT_PATH_STORAGE?=storage:distributed-pytorch

PROJECT_PATH_ENV?=/distributed-pytorch

PROJECT_ENVIRONMENT?=/project-env

##### JOB NAMES #####

PROJECT_POSTFIX?=distributed-pytorch

SETUP_JOB?=setup-$(PROJECT_POSTFIX)
TRAIN_JOB?=train-$(PROJECT_POSTFIX)
DIST_JOB?=dist-$(PROJECT_POSTFIX)
DEVELOP_JOB?=develop-$(PROJECT_POSTFIX)
JUPYTER_JOB?=jupyter-$(PROJECT_POSTFIX)
TENSORBOARD_JOB?=tensorboard-$(PROJECT_POSTFIX)
FILEBROWSER_JOB?=filebrowser-$(PROJECT_POSTFIX)

##### ENVIRONMENTS #####

BASE_ENV_NAME?=neuromation/base:latest
CUSTOM_ENV_NAME?=image:neuromation-$(PROJECT_POSTFIX):$(VERSION)

##### VARIABLES YOU MAY WANT TO MODIFY #####

# Jupyter mode. Available options: notebook (to run Jupyter Notebook), lab (to run JupyterLab).
JUPYTER_MODE?=notebook

# Location of your dataset on the platform storage. Example:
# DATA_DIR_STORAGE?=storage:datasets/cifar10
DATA_DIR_STORAGE?=$(PROJECT_PATH_STORAGE)/$(DATA_DIR)

# Location of your results directory on the platform storage.
RESULTS_DIR_STORAGE?=$(PROJECT_PATH_STORAGE)/$(RESULTS_DIR)

# The type of the training machine (run `neuro config show` to see the list of available types).
PRESET?=gpu-k80-small

# HTTP authentication (via cookies) for the job's HTTP link.
# Applied only to jupyter, tensorboard and filebrowser jobs.
# Set `HTTP_AUTH=--no-http-auth` to disable any authentication.
# WARNING: removing authentication might disclose your sensitive data stored in the job.
HTTP_AUTH?=--http-auth

# When running the training job, wait until it gets actually running,
# and stream logs to the standard output.
# Set any other value to disable this feature: `TRAIN_STREAM_LOGS=no`.
TRAIN_STREAM_LOGS?=yes

# Command to run training inside the environment. Example:
SCRIPT_NAME=worker.sh
CONFIG_NAME=test_bert.cfg

TRAIN_CMD="bash -c 'cd $(PROJECT_PATH_ENV) && python -u $(CODE_DIR)/train.py -c $(CONFIG_DIR)/$(CONFIG_NAME)'"
DIST_CMD="bash -c 'cd $(PROJECT_PATH_ENV) && chmod +x $(SCRIPTS_DIR)/$(SCRIPT_NAME) && $(SCRIPTS_DIR)/$(SCRIPT_NAME) -c $(CONFIG_DIR)/$(CONFIG_NAME)'"

LOCAL_PORT?=2211

##### SECRETS ######

# Google Cloud integration settings:
GCP_SECRET_FILE?=neuro-job-key.json
GCP_SECRET_PATH_LOCAL=${CONFIG_DIR}/${GCP_SECRET_FILE}
GCP_SECRET_PATH_ENV=${PROJECT_PATH_ENV}/${GCP_SECRET_PATH_LOCAL}

# AWS integration settings:
AWS_SECRET_FILE?=aws-credentials.txt
AWS_SECRET_PATH_LOCAL=${CONFIG_DIR}/${AWS_SECRET_FILE}
AWS_SECRET_PATH_ENV=${PROJECT_PATH_ENV}/${AWS_SECRET_PATH_LOCAL}

# Weights and Biases integration settings:
WANDB_SECRET_FILE?=wandb-token.txt

WANDB_SECRET_PATH_LOCAL=${CONFIG_DIR}/${WANDB_SECRET_FILE}
WANDB_SECRET_PATH_ENV=${PROJECT_PATH_ENV}/${WANDB_SECRET_PATH_LOCAL}

##### COMMANDS #####

APT?=apt-get -qq
PIP?=pip install --progress-bar=off -U --no-cache-dir
NEURO?=neuro


ifeq (${TRAIN_STREAM_LOGS}, yes)
	TRAIN_WAIT_START_OPTION=--wait-start --detach
else
	TRAIN_WAIT_START_OPTION=
endif

ifeq (${DIST_WAIT_START}, yes)
	DIST_WAIT_START_OPTION=--wait-start
else
	DIST_WAIT_START_OPTION=
endif

# Check if GCP authentication file exists, then set up variables
ifneq ($(wildcard ${GCP_SECRET_PATH_LOCAL}),)
	OPTION_GCP_CREDENTIALS=\
		--env GOOGLE_APPLICATION_CREDENTIALS="${GCP_SECRET_PATH_ENV}" \
		--env GCP_SERVICE_ACCOUNT_KEY_PATH="${GCP_SECRET_PATH_ENV}"
else
	OPTION_GCP_CREDENTIALS=
endif

# Check if AWS authentication file exists, then set up variables
ifneq ($(wildcard ${AWS_SECRET_PATH_LOCAL}),)
	OPTION_AWS_CREDENTIALS=\
		--env AWS_CONFIG_FILE="${AWS_SECRET_PATH_ENV}" \
		--env NM_AWS_CONFIG_FILE="${AWS_SECRET_PATH_ENV}"
else
	OPTION_AWS_CREDENTIALS=
endif

# Check if Weights & Biases key file exists, then set up variables
ifneq ($(wildcard ${WANDB_SECRET_PATH_LOCAL}),)
	OPTION_WANDB_CREDENTIALS=--env NM_WANDB_TOKEN_PATH="${WANDB_SECRET_PATH_ENV}"
else
	OPTION_WANDB_CREDENTIALS=
endif

##### HELP #####

.PHONY: help
help:
	@# generate help message by parsing current Makefile
	@# idea: https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
	@grep -hE '^[a-zA-Z_-]+:[^#]*?### .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

##### SETUP #####

.PHONY: setup
setup: ### Setup remote environment
	$(NEURO) mkdir --parents $(PROJECT_PATH_STORAGE) \
		$(PROJECT_PATH_STORAGE)/$(CODE_DIR) \
		$(DATA_DIR_STORAGE) \
		$(PROJECT_PATH_STORAGE)/$(CONFIG_DIR) \
		$(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR) \
		$(PROJECT_PATH_STORAGE)/$(SCRIPTS_DIR) \
		$(RESULTS_DIR_STORAGE)
	$(NEURO) run \
		--name $(SETUP_JOB) \
		--description "$(PROJECT_ID):setup" \
		--preset cpu-large \
		--detach \
		--env JOB_TIMEOUT=1h \
		--volume $(PROJECT_PATH_STORAGE):$(PROJECT_PATH_ENV):rw \
		$(BASE_ENV_NAME) \
		'sleep infinity'
	for file in $(PROJECT_FILES); do $(NEURO) cp ./$$file $(PROJECT_PATH_STORAGE)/$$file; done
	$(NEURO) exec --no-key-check $(SETUP_JOB) "bash -c 'chmod +x $(PROJECT_PATH_ENV)/project_configure.sh && $(PROJECT_PATH_ENV)/project_configure.sh'"
	$(NEURO) exec --no-key-check $(SETUP_JOB) "bash -c 'export DEBIAN_FRONTEND=noninteractive && $(APT) update && cat $(PROJECT_PATH_ENV)/apt.txt | xargs -I % $(APT) install --no-install-recommends % && $(APT) clean && $(APT) autoremove && rm -rf /var/lib/apt/lists/*'"
	$(NEURO) exec --no-key-check $(SETUP_JOB) "bash -c '$(PIP) -r $(PROJECT_PATH_ENV)/requirements.txt'"
	$(NEURO) --network-timeout 300 job save $(SETUP_JOB) $(CUSTOM_ENV_NAME)
	$(NEURO) kill $(SETUP_JOB)
	@touch .setup_done

.PHONY: kill-setup
kill-setup:  ### Terminate the setup job (if it was not killed by `make setup` itself)
	$(NEURO) kill $(SETUP_JOB)

.PHONY: _check_setup
_check_setup:
	@test -f .setup_done || { echo "Please run 'make setup' first"; false; }

##### STORAGE #####

.PHONY: upload-code
upload-code: _check_setup  ### Upload code directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(CODE_DIR) $(PROJECT_PATH_STORAGE)/$(CODE_DIR)

.PHONY: download-code
download-code: _check_setup  ### Download code directory from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(PROJECT_PATH_STORAGE)/$(CODE_DIR) $(CODE_DIR)

.PHONY: clean-code
clean-code: _check_setup  ### Delete code directory from the platform storage
	$(NEURO) rm --recursive $(PROJECT_PATH_STORAGE)/$(CODE_DIR)/*

.PHONY: upload-scripts
upload-scripts: _check_setup  ### Upload directory with scripts to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(SCRIPTS_DIR) $(PROJECT_PATH_STORAGE)/$(SCRIPTS_DIR)

.PHONY: download-scripts
download-scripts: _check_setup  ### Download directory with scripts from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(PROJECT_PATH_STORAGE)/$(SCRIPTS_DIR) $(SCRIPTS_DIR)

.PHONY: clean-scripts
clean-scripts: _check_setup  ### Delete directory with scripts from the platform storage
	$(NEURO) rm --recursive $(PROJECT_PATH_STORAGE)/$(SCRIPTS_DIR)/*

.PHONY: upload-data
upload-data: _check_setup  ### Upload data directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(DATA_DIR) $(DATA_DIR_STORAGE)

.PHONY: download-data
download-data: _check_setup  ### Download data directory from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(DATA_DIR_STORAGE) $(DATA_DIR)

.PHONY: clean-data
clean-data: _check_setup  ### Delete data directory from the platform storage
	$(NEURO) rm --recursive $(DATA_DIR_STORAGE)/*

.PHONY: upload-config
upload-config: _check_setup  ### Upload config directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(CONFIG_DIR) $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR)

.PHONY: download-config
download-config: _check_setup  ### Download config directory from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR) $(CONFIG_DIR)

.PHONY: clean-config
clean-config: _check_setup  ### Delete config directory from the platform storage
	$(NEURO) rm --recursive $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR)/*

.PHONY: upload-notebooks
upload-notebooks: _check_setup  ### Upload notebooks directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(NOTEBOOKS_DIR) $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR)

.PHONY: download-notebooks
download-notebooks: _check_setup  ### Download notebooks directory from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR) $(NOTEBOOKS_DIR)

.PHONY: clean-notebooks
clean-notebooks: _check_setup  ### Delete notebooks directory from the platform storage
	$(NEURO) rm --recursive $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR)/*

.PHONY: upload-results
upload-results: _check_setup  ### Upload results directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(RESULTS_DIR) $(RESULTS_DIR_STORAGE)

.PHONY: download-results
download-results: _check_setup  ### Download results directory from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(RESULTS_DIR_STORAGE) $(RESULTS_DIR)

.PHONY: clean-results
clean-results: _check_setup  ### Delete results directory from the platform storage
	$(NEURO) rm --recursive $(RESULTS_DIR_STORAGE)/*

.PHONY: upload-all
upload-all: upload-code upload-scripts upload-data upload-config upload-notebooks upload-results  ### Upload code, scripts, data, config, notebooks, and results directories to the platform storage

.PHONY: download-all
download-all: download-code download-scripts download-data download-config download-notebooks download-results  ### Download code, data, config, notebooks, and results directories from the platform storage

.PHONY: clean-all
clean-all: clean-code clean-scripts clean-data clean-config clean-notebooks clean-results  ### Delete code, data, config, notebooks, and results directories from the platform storage

##### Google Cloud Integration #####

.PHONY: gcloud-check-auth
gcloud-check-auth:  ### Check if the file containing Google Cloud service account key exists
	@echo "Using variable: GCP_SECRET_FILE='${GCP_SECRET_FILE}'"
	@test "${OPTION_GCP_CREDENTIALS}" \
		&& echo "Google Cloud will be authenticated via service account key file: '$${PWD}/${GCP_SECRET_PATH_LOCAL}'" \
		|| { echo "ERROR: Not found Google Cloud service account key file: '$${PWD}/${GCP_SECRET_PATH_LOCAL}'"; \
			echo "Please save the key file named GCP_SECRET_FILE='${GCP_SECRET_FILE}' to './${CONFIG_DIR}/'"; \
			false; }

##### AWS Integration #####

.PHONY: aws-check-auth
aws-check-auth:  ### Check if the file containing AWS user account credentials exists
	@echo "Using variable: AWS_SECRET_FILE='${AWS_SECRET_FILE}'"
	@test "${OPTION_AWS_CREDENTIALS}" \
		&& echo "AWS will be authenticated via user account credentials file: '$${PWD}/${AWS_SECRET_PATH_LOCAL}'" \
		|| { echo "ERROR: Not found AWS user account credentials file: '$${PWD}/${AWS_SECRET_PATH_LOCAL}'"; \
			echo "Please save the key file named AWS_SECRET_FILE='${AWS_SECRET_FILE}' to './${CONFIG_DIR}/'"; \
			false; }

##### WandB Integration #####

.PHONY: wandb-check-auth
wandb-check-auth:  ### Check if the file Weights and Biases authentication file exists
	@echo Using variable: WANDB_SECRET_FILE='${WANDB_SECRET_FILE}'
	@test "${OPTION_WANDB_CREDENTIALS}" \
		&& echo "Weights & Biases will be authenticated via key file: '$${PWD}/${WANDB_SECRET_PATH_LOCAL}'" \
		|| { echo "ERROR: Not found Weights & Biases key file: '$${PWD}/${WANDB_SECRET_PATH_LOCAL}'"; \
			echo "Please save the key file named WANDB_SECRET_FILE='${WANDB_SECRET_FILE}' to './${CONFIG_DIR}/'"; \
			false; }

##### JOBS #####
RUN?=base

.PHONY: develop
develop: _check_setup upload-code upload-scripts upload-config upload-notebooks  ### Run a development job
	$(NEURO) run \
		--name $(DEVELOP_JOB)-$(RUN) \
		--description "$(PROJECT_ID):develop" \
		--preset $(PRESET) \
		--detach \
		--volume $(DATA_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(DATA_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CODE_DIR):$(PROJECT_PATH_ENV)/$(CODE_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR):$(PROJECT_PATH_ENV)/$(CONFIG_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(SCRIPTS_DIR):$(PROJECT_PATH_ENV)/$(SCRIPTS_DIR):rw \
		--volume $(RESULTS_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(RESULTS_DIR):rw \
		--env PYTHONPATH=$(PROJECT_PATH_ENV) \
		--env EXPOSE_SSH=yes \
		--env JOB_TIMEOUT=1d \
		${OPTION_GCP_CREDENTIALS} ${OPTION_AWS_CREDENTIALS} ${OPTION_WANDB_CREDENTIALS} \
		$(CUSTOM_ENV_NAME) \
		sleep infinity

.PHONY: connect-develop
connect-develop:  ### Connect to the remote shell running on the development job
	$(NEURO) exec --no-key-check $(DEVELOP_JOB)-$(RUN) bash

.PHONY: logs-develop
logs-develop:  ### Connect to the remote shell running on the development job
	$(NEURO) logs $(DEVELOP_JOB)

.PHONY: port-forward-develop
port-forward-develop:  ### Forward SSH port to localhost for remote debugging
	@test ${LOCAL_PORT} || { echo 'Please set up env var LOCAL_PORT'; false; }
	$(NEURO) port-forward $(DEVELOP_JOB) $(LOCAL_PORT):22

.PHONY: kill-develop
kill-develop:  ### Terminate the development job
	$(NEURO) kill $(DEVELOP_JOB)

.PHONY: train
train: _check_setup upload-code upload-scripts upload-config   ### Run a training job (set up env var 'RUN' to specify the training job),
	$(NEURO) run \
		--name $(TRAIN_JOB)-$(RUN) \
		--description "$(PROJECT_ID):train" \
		--preset $(PRESET) \
		--detach \
		$(TRAIN_WAIT_START_OPTION) \
		--volume $(DATA_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(DATA_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CODE_DIR):$(PROJECT_PATH_ENV)/$(CODE_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR):$(PROJECT_PATH_ENV)/$(CONFIG_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(SCRIPTS_DIR):$(PROJECT_PATH_ENV)/$(SCRIPTS_DIR):ro \
		--volume $(RESULTS_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(RESULTS_DIR):rw \
		--env PYTHONPATH=$(PROJECT_PATH_ENV) \
		--env EXPOSE_SSH=yes \
		--env JOB_TIMEOUT=0 \
		${OPTION_GCP_CREDENTIALS} ${OPTION_AWS_CREDENTIALS} ${OPTION_WANDB_CREDENTIALS} \
		$(CUSTOM_ENV_NAME) \
		$(TRAIN_CMD)
ifeq (${TRAIN_STREAM_LOGS}, yes)
	@echo "Streaming logs of the job $(TRAIN_JOB)-$(RUN)"
	$(NEURO) exec --no-key-check -T $(TRAIN_JOB)-$(RUN) "tail -f -n 1000000 /output" || echo -e "Stopped streaming logs.\nUse 'neuro logs <job>' to see full logs."
endif

.PHONY: kill-train
kill-train:  ### Terminate the training job (set up env var 'RUN' to specify the training job)
	$(NEURO) kill $(TRAIN_JOB)-$(RUN)

.PHONY: kill-train-all
kill-train-all:  ### Terminate all training jobs you have submitted
	jobs=$$(neuro --quiet ps --description="$(PROJECT_ID):train") && \
	$(NEURO) kill $${jobs:-placeholder}

.PHONY: connect-train
connect-train: _check_setup  ### Connect to the remote shell running on the training job (set up env var 'RUN' to specify the training job)
	$(NEURO) exec --no-key-check $(TRAIN_JOB)-$(RUN) bash

.PHONY: dist
dist: _check_setup upload-code upload-scripts upload-config   ### Run a distributed training job (set up env var 'RUN' to specify the training job),
	$(NEURO) run \
		--name $(DIST_JOB)-$(RUN) \
		--description "$(PROJECT_ID):dist" \
		--preset $(PRESET) \
		--detach \
		$(DIST_WAIT_START_OPTION) \
		--volume $(DATA_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(DATA_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CODE_DIR):$(PROJECT_PATH_ENV)/$(CODE_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR):$(PROJECT_PATH_ENV)/$(CONFIG_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(SCRIPTS_DIR):$(PROJECT_PATH_ENV)/$(SCRIPTS_DIR):rw \
		--volume $(RESULTS_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(RESULTS_DIR):rw \
		--env PYTHONPATH=$(PROJECT_PATH_ENV) \
		--env EXPOSE_SSH=yes \
		--env JOB_TIMEOUT=0 \
		--env LOCAL_RANK=$(LOCAL_RANK) \
		--env WORLD_SIZE=$(WORLD_SIZE) \
		--env MASTER_IP=$(MASTER_IP) \
		--env MASTER_PORT=$(MASTER_PORT) \
		${OPTION_GCP_CREDENTIALS} ${OPTION_AWS_CREDENTIALS} ${OPTION_WANDB_CREDENTIALS} \
		$(CUSTOM_ENV_NAME) \
		$(DIST_CMD)

.PHONY: kill-dist
kill-dist:  ### Terminate the distributed training job (set up env var 'RUN' to specify the training job)
	$(NEURO) kill $(DIST_JOB)-$(RUN)

.PHONY: kill-dist-all
kill-dist-all:  ### Terminate all distributed training jobs you have submitted
	jobs=$$(neuro --quiet ps --description="$(PROJECT_ID):dist") && \
	$(NEURO) kill $${jobs:-placeholder}

.PHONY: jupyter
jupyter: _check_setup upload-config upload-code upload-scripts upload-notebooks ### Run a job with Jupyter Notebook and open UI in the default browser
	$(NEURO) run \
		--name $(JUPYTER_JOB) \
		--description "$(PROJECT_ID):jupyter" \
		--preset $(PRESET) \
		--http 8888 \
		$(HTTP_AUTH) \
		--browse \
		--detach \
		--volume $(DATA_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(DATA_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(CODE_DIR):$(PROJECT_PATH_ENV)/$(CODE_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR):$(PROJECT_PATH_ENV)/$(CONFIG_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR):$(PROJECT_PATH_ENV)/$(NOTEBOOKS_DIR):rw \
		--volume $(RESULTS_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(RESULTS_DIR):rw \
		--env JOB_TIMEOUT=1d \
		--env PYTHONPATH=$(PROJECT_PATH_ENV) \
		${OPTION_GCP_CREDENTIALS} ${OPTION_AWS_CREDENTIALS} ${OPTION_WANDB_CREDENTIALS} \
		$(CUSTOM_ENV_NAME) \
		jupyter $(JUPYTER_MODE) --no-browser --ip=0.0.0.0 --allow-root --NotebookApp.token= --notebook-dir=$(PROJECT_PATH_ENV)

.PHONY: kill-jupyter
kill-jupyter:  ### Terminate the job with Jupyter Notebook
	$(NEURO) kill $(JUPYTER_JOB)

.PHONY: jupyterlab
jupyterlab:  ### Run a job with JupyterLab and open UI in the default browser
	@make --silent jupyter JUPYTER_MODE=lab

.PHONY: kill-jupyterlab
kill-jupyterlab:  ### Terminate the job with JupyterLab
	@make --silent kill-jupyter

.PHONY: tensorboard
tensorboard: _check_setup  ### Run a job with TensorBoard and open UI in the default browser
	$(NEURO) run \
		--name $(TENSORBOARD_JOB) \
		--preset cpu-small \
		--description "$(PROJECT_ID):tensorboard" \
		--http 6006 \
		$(HTTP_AUTH) \
		--browse \
		--env JOB_TIMEOUT=1d \
		--volume $(RESULTS_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(RESULTS_DIR):ro \
		$(CUSTOM_ENV_NAME) \
		tensorboard --host=0.0.0.0 --logdir=$(PROJECT_PATH_ENV)/$(RESULTS_DIR)

.PHONY: kill-tensorboard
kill-tensorboard:  ### Terminate the job with TensorBoard
	$(NEURO) kill $(TENSORBOARD_JOB)

.PHONY: filebrowser
filebrowser: _check_setup  ### Run a job with File Browser and open UI in the default browser
	$(NEURO) run \
		--name $(FILEBROWSER_JOB) \
		--description "$(PROJECT_ID):filebrowser" \
		--preset cpu-small \
		--http 80 \
		$(HTTP_AUTH) \
		--browse \
		--env JOB_TIMEOUT=1d \
		--volume $(PROJECT_PATH_STORAGE):/srv:rw \
		filebrowser/filebrowser \
		--noauth

.PHONY: kill-filebrowser
kill-filebrowser:  ### Terminate the job with File Browser
	$(NEURO) kill $(FILEBROWSER_JOB)

.PHONY: kill-all
kill-all: kill-develop kill-train-all kill-jupyter kill-tensorboard kill-filebrowser kill-setup  ### Terminate all jobs of this project

##### LOCAL #####

.PHONY: setup-local
setup-local:  ### Install pip requirements locally
	$(PIP) -r requirements.txt

.PHONY: format
format:  ### Automatically format the code
	isort -rc modules
	black modules

.PHONY: lint
lint:  ### Run static code analysis locally
	isort -c -rc modules
	black --check modules
	mypy modules
	flake8 modules

##### MISC #####

.PHONY: ps
ps:  ### List all running and pending jobs
	$(NEURO) ps