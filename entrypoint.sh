#!/bin/bash -l

set -e

export APPLICATION_HELMFILE=$(pwd)/${HELMFILE_PATH}/${HELMFILE}

source /etc/profile.d/aws.sh

# Used for debugging
aws sts --region ${AWS_REGION} get-caller-identity

# Login to Kubernetes Cluster.
aws eks --region ${AWS_REGION} update-kubeconfig --name ${CLUSTER_NAME}

# Read platform specific configs/info
chamber export platform/${CLUSTER_NAME}/${ENVIRONMENT} --format yaml | yq --exit-status --no-colors  eval '{"platform": .}' - > /tmp/platform.yaml

DEBUG_ARGS=""

if [[ "${HELM_DEBUG}" == "true" ]]; then
#	helmfile --namespace ${NAMESPACE} --environment ${ENVIRONMENT} --file /deploy/helmfile.yaml template
	DEBUG_ARGS=" --debug"
fi

# approach 1: --state-values-set flag. This doesn't seem to propagate from helmfile.yaml to the imported release helmfile
if [[ -n "$HELM_VALUES" ]]; then
  HELM_VALUES_FLAG="--state-values-set ${HELM_VALUES}"
fi

# apprach 2: contents of a file to include
if [[ -n "$HELM_VALUES_FILE_CONTENTS" ]]; then
  export HELM_VALUES_FILE="/tmp/extra_helm_values.yml"
  echo "$HELM_VALUES_FILE_CONTENTS" > "$HELM_VALUES_FILE"
fi

if [[ "${OPERATION}" == "deploy" ]]; then
	echo "Deploying..."

	OPERATION_COMMAND="helmfile ${HELM_VALUES_FLAG} ${HELM_VALUES_FILE_FLAG} --namespace ${NAMESPACE} --environment ${ENVIRONMENT} --file /deploy/helmfile.yaml $DEBUG_ARGS apply"
	echo "Executing: ${OPERATION_COMMAND}"
	${OPERATION_COMMAND}

  echo "Listing releases..."
	RELEASES=$(helmfile --namespace ${NAMESPACE} --environment ${ENVIRONMENT} --file /deploy/helmfile.yaml list --output json | jq .[].name -r)
	for RELEASE in ${RELEASES}
  do
	ENTRYPOINT=$(kubectl --namespace ${NAMESPACE} get -l ${RELEASE_LABEL_NAME}=${RELEASE} ingress --output=jsonpath='{.items[*].metadata.annotations.outputs\.webapp-url}')
		if [[ "${ENTRYPOINT}" != "" ]]; then
			echo "::set-output name=webapp-url::${ENTRYPOINT}"
  	fi
  done


elif [[ "${OPERATION}" == "destroy" ]]; then

	set +e
	kubectl get ns ${NAMESPACE}
	NAMESPACE_EXISTS=$?
	set -e

	if [[ ${NAMESPACE_EXISTS} -eq 0  ]]; then
		OPERATION_COMMAND="helmfile --namespace ${NAMESPACE} --environment ${ENVIRONMENT} --file /deploy/helmfile.yaml $DEBUG_ARGS destroy"
		echo "Executing: ${OPERATION_COMMAND}"
		${OPERATION_COMMAND}

		RELEASES_COUNTS=$(helm --namespace ${NAMESPACE} list --output json | jq 'length')

    if [[ "${RELEASES_COUNTS}" == "0" ]]; then
    	kubectl delete ns ${NAMESPACE}
    fi
	fi
fi
