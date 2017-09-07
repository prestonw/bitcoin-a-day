#!/bin/bash
owner_id=$(aws ec2 describe-security-groups --group-names 'Default' --query 'SecurityGroups[0].OwnerId' --output text)

# Encrypt bitstamp-properties.json
echo Generating password for the bitstamp-properties.json file.
bitstamp_properties_password=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
echo Encrypting bitstamp-properties.json as bitstamp-properties.json.encrypted.
openssl enc -e -a -nosalt -pass pass:"${bitstamp_properties_password}" -in bitstamp-properties.json -out bitstamp-properties.json.encrypted -aes-256-cbc
echo Password to decrypt bitstamp-properties.json.encrypted file: ${bitstamp_properties_password} >> output.txt

random_id=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)

# Create S3 bucket
bucket_name=bitcoin-a-day-$random_id
s3_bucket_uri='s3://'"${bucket_name}"
echo Creating S3 bucket "${bucket_name}", S3 URI: "${s3_bucket_uri}".
aws s3 mb "${s3_bucket_uri}"
echo S3 bucket name: "${bucket_name}" >> output.txt
echo S3 bucket URI: "${s3_bucket_uri}" >> output.txt

# Upload bitstamp-properties.json.encrypted to S3 bucket
echo Uploading bitstamp-properties.json.encrypted to S3 bucket "${bucket_name}"
aws s3 cp bitstamp-properties.json.encrypted "${s3_bucket_uri}"

# Create IAM policy to access bitstamp-properties.json.encrypted
iam_policy_name=bitcoin-a-day-"${random_id}"-bitstamp-properties-access
sed -e s!@bucket_name@!"${bucket_name}"!g bitstamp-properties-access-policy-template.json > bitstamp-properties-access-policy.json
echo Creating IAM policy "${iam_policy_name}" to access bitstamp-properties.json.encrypted file
aws iam create-policy --policy-name "${iam_policy_name}" --policy-document file://bitstamp-properties-access-policy.json --output text
echo IAM policy name: "${iam_policy_name}" >> output.txt
iam_policy_arn_query='Policies[?PolicyName==`'"${iam_policy_name}"'`].Arn'
iam_policy_arn=$(aws iam list-policies --query "${iam_policy_arn_query}" --output text)
echo IAM policy ARN: "${iam_policy_arn}" >> output.txt

# Create IAM role for the lambda function
iam_role_name=bitcoin-a-day-"${random_id}"-lambda
echo Creating IAM role "${iam_role_name}" for the lambda function.
aws iam create-role --role-name "${iam_role_name}" --assume-role-policy-document file://bitcoin-a-day-lambda-role-policy-document.json --query "Role.Arn" --output text
iam_role_arn_query='Roles[?RoleName==`'"${iam_role_name}"'`].Arn'
iam_role_arn=$(aws iam list-roles --query "${iam_role_arn_query}" --output text)
echo IAM role name for the lambda function: ${iam_role_name} >> output.txt
echo IAM role ARN for the lambda function: ${iam_role_arn} >> output.txt

echo Attaching IAM policy "${iam_policy_arn}" to lambda function role "${iam_role_name}"
aws iam attach-role-policy --role-name "${iam_role_name}" --policy-arn "${iam_policy_arn}"

echo Attaching IAM policy arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole to lambda function role "${iam_role_name}"
aws iam attach-role-policy --role-name "${iam_role_name}" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

echo Creating encryption key policy.
sed -e "s!@owner_id@!${owner_id}!g; s!@iam_role_arn@!${iam_role_arn}!g" encryption-key-policy-template.json > encryption-key-policy.json
echo Creating encryption key.
encryption_key_id=$(aws kms create-key --policy fileb://encryption-key-policy.json --description "Bitcoin A Day" --query KeyMetadata.KeyId --output text)
echo Encryption key id: ${encryption_key_id} >> output.txt
encryption_key_alias=alias/bitcoin-a-day-"${random_id}"-encryption-key
echo Creating encryption key alias "${encryption_key_alias}".
aws kms create-alias --alias-name "${encryption_key_alias}" --target-key-id "${encryption_key_id}"
echo Encryption key alias: ${encryption_key_alias} >> output.txt