# LocalStack Init Scripts

This directory is for future initialization scripts that run when LocalStack starts.

Scripts placed here will be executed when LocalStack reaches the "ready" state.

## Usage

Create shell scripts in this directory:
- They will be mounted to `/etc/localstack/init/ready.d/` in the container
- They should be executable (`chmod +x`)
- They run in alphanumeric order

## Example

```bash
#!/bin/bash
# 01-create-test-resources.sh

# Create a test S3 bucket
aws --endpoint-url=http://localhost:4566 s3 mb s3://test-bucket
```

## References

- [LocalStack Init Hooks](https://docs.localstack.cloud/references/init-hooks/)
