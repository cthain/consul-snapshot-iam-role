# Consul snapshot agent IAM assume role

This project:
- Deploys an EKS cluster on AWS.
- Installs Consul enterprise on the k8s cluster.
- Configures the `consul-snapshot-agent` service account to get IAM credentials via an IAM role.
- Configures the `consul-snapshot-agent` to save snapshots in S3 using the IAM creds from the service account.

## Build and publish Consul

During development/test publish a Consul enterprise dev image to a private ECR:

```shell
export AWS_REGION="us-west-2"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) ; echo "AWS_ACCOUNT_ID = $AWS_ACCOUNT_ID"
consul-enterprise$ make dev-docker
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
aws ecr create-repository --repository-name consul-enterprise --region ${AWS_REGION}
docker tag consul-dev:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/consul-enterprise:dev
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/consul-enterprise:dev
```

## Stand up the infrastructure

### Terraform apply

```shell
terraform init
tf apply -auto-approve -var name=$USER -var "consul_image=${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/consul-enterprise:dev" -var "consul_license_path=/home/${USER}/.ssh/consul.license"
```

### Set up environment

```shell
export EKS_CLUSTER_ID=$(terraform output -json | jq -r '.eks_cluster_id.value')
export OIDC_ID=$(aws eks describe-cluster --region ${AWS_REGION} --name ${EKS_CLUSTER_ID} --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
export OIDC_PROVIDER=$(aws eks describe-cluster --region ${AWS_REGION} --name ${EKS_CLUSTER_ID} --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///"); echo "OIDC_PROVIDER = $OIDC_PROVIDER"
export NAMESPACE="default"
export SVC_ACCOUNT=consul-snapshot-agent
export ASSUME_ROLE_POLICY=consul-snapshot-assume-role
export ROLE_NAME=consul-snapshot-agent
export POLICY_NAME=manage-consul-snapshots-s3
export POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
```

## Configure service accounts

### Setup OIDC provide for EKS cluster

```shell
[[ -z "$(aws iam list-open-id-connect-providers | grep $OIDC_ID)" ]] && \
  eksctl utils associate-iam-oidc-provider --region ${AWS_REGION} --cluster ${EKS_CLUSTER_ID} --approve
```

Create the S3 snapshot management policy

```shell
cat > "${POLICY_NAME}.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucketVersions",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::*"
    }
  ]
}
EOF
aws iam create-policy --policy-name ${POLICY_NAME} --policy-document file://${POLICY_NAME}.json --description "Allows management of Consul snapshots in S3"
```

Create the snapshot agent role and attach an assume role policy that allows the service account to perform an `sts:AssumeRoleWithWebIdentity`

```shell
cat > "${ASSUME_ROLE_POLICY}.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SVC_ACCOUNT}"
        }
      }
    }
  ]
}
EOF
```

Create the role. Provide the assume-role policy so that the `consul-snapshot-agent` pod can assume the role.

```shell
aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://${ASSUME_ROLE_POLICY}.json --description "Allow Consul snapshot agent pods to assume role"
```

Attach the S3 snapshot management policy to the role for the `consul-snapshot-agent` service account.

```shell
aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn=${POLICY_ARN}
```

Install Consul

```shell
consul-k8s install -namespace ${NAMESPACE} -config-file values.yaml -auto-approve
```

Annotate the service account for the `consul-snapshot-agent` with the new role.

```shell
kubectl annotate serviceaccount -n ${NAMESPACE} ${SVC_ACCOUNT} eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}
```

## Clean up

```shell
consul-k8s uninstall -name consul -namespace ${NAMESPACE} -wipe-data -auto-approve
aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn=${POLICY_ARN}
aws iam delete-policy --policy-arn=${POLICY_ARN}
aws iam delete-role --role-name ${ROLE_NAME}
```
