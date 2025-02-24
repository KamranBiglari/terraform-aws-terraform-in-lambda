# terraform-aws-terraform-in-lambda


# Usage

```
aws lambda invoke \
  --function-name terraform-lambda-function \
  --payload '{
    "aws_access_key": "YOUR_ACCESS_KEY",
    "aws_secret_key": "YOUR_SECRET_KEY",
    "aws_session_token": "YOUR_SESSION_TOKEN",
    "tf_code": "BASE64_ENCODED_OF_ZIPPED_TF_CODE",
    "backend": "BASE64_ENCODED_BACKEND",
    "command": "apply"
  }'
```