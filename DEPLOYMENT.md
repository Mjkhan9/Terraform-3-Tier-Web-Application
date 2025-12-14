# Deployment Guide

## Quick Deployment in AWS CloudShell

AWS CloudShell comes with Terraform pre-installed, making deployment straightforward.

### Step 1: Clone Repository

```bash
git clone <your-repository-url>
cd Terraform-3-Tier-Web-Application
```

### Step 2: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # or use your preferred editor
```

**Required**: Set your database password:
```hcl
db_password = "YourSecurePassword123!"
```

### Step 3: Deploy

**Option A: Using the deployment script**
```bash
chmod +x deploy.sh
./deploy.sh
```

**Option B: Manual deployment**
```bash
terraform init
terraform plan
terraform apply
```

### Step 4: Access Application

After deployment completes (5-10 minutes), get the URL:

```bash
terraform output application_url
```

## Deployment Checklist

- [ ] AWS credentials configured
- [ ] Terraform installed (>= 1.0)
- [ ] `terraform.tfvars` created and configured
- [ ] Database password set
- [ ] Sufficient AWS service quotas
- [ ] Region selected (us-east-1 recommended for Free Tier)

## Pre-Deployment Verification

### Check AWS Credentials

```bash
aws sts get-caller-identity
```

### Verify Service Quotas

Ensure you have available quotas for:
- VPCs: 5 per region (default)
- NAT Gateways: 5 per AZ (default)
- EC2 Instances: 20 per region (default)
- RDS Instances: 40 per region (default)

### Check Region

```bash
aws configure get region
```

Or set it:
```bash
aws configure set region us-east-1
```

## Post-Deployment Verification

### 1. Check ALB Status

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`3-tier-web-app-alb`]'
```

### 2. Check Target Health

```bash
TG_ARN=$(terraform output -raw target_group_arn 2>/dev/null || echo "")
if [ ! -z "$TG_ARN" ]; then
  aws elbv2 describe-target-health --target-group-arn $TG_ARN
fi
```

### 3. Check Auto Scaling Group

```bash
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?AutoScalingGroupName==`3-tier-web-app-asg`]'
```

### 4. Check RDS Status

```bash
aws rds describe-db-instances --query 'DBInstances[?DBInstanceIdentifier==`3-tier-web-app-db`]'
```

### 5. Test Application

```bash
ALB_URL=$(terraform output -raw application_url)
curl $ALB_URL/health
```

## Troubleshooting Deployment

### Issue: Terraform Init Fails

**Solution**: Check internet connectivity and AWS credentials

```bash
aws sts get-caller-identity
```

### Issue: NAT Gateway Creation Fails

**Solution**: Check Elastic IP limits (5 per region default)

```bash
aws ec2 describe-addresses --query 'length(Addresses)'
```

### Issue: RDS Creation Fails

**Solution**: Check RDS instance limits and DB subnet group

```bash
aws rds describe-db-instances --query 'length(DBInstances)'
```

### Issue: EC2 Instances Not Launching

**Solution**: Check Auto Scaling Group and launch template

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names 3-tier-web-app-asg
```

### Issue: Application Not Responding

**Solution**: 
1. Wait 5-10 minutes for initialization
2. Check target health
3. View application logs:

```bash
aws logs tail /aws/ec2/3-tier-web-app --follow
```

## Deployment Time Estimates

- **Terraform Plan**: 30-60 seconds
- **VPC Creation**: 1-2 minutes
- **NAT Gateway**: 3-5 minutes
- **RDS Database**: 5-10 minutes
- **EC2 Instances**: 2-3 minutes
- **Application Initialization**: 3-5 minutes

**Total**: ~15-25 minutes

## Rollback Procedure

If deployment fails or needs to be rolled back:

```bash
terraform destroy
```

**Warning**: This will delete all resources. Ensure you have backups if needed.

## Partial Deployment Recovery

If deployment fails partway through:

1. **Review Error**: Check Terraform output for specific error
2. **Fix Issue**: Address the root cause
3. **Re-run Apply**: Terraform will attempt to continue

```bash
terraform apply
```

## State Management

### Local State (Default)

State is stored in `terraform.tfstate` file locally.

### Remote State (Recommended for Teams)

Uncomment backend configuration in `versions.tf`:

```hcl
backend "s3" {
  bucket = "your-terraform-state-bucket"
  key    = "3-tier-app/terraform.tfstate"
  region = "us-east-1"
  encrypt = true
}
```

Then run:
```bash
terraform init -migrate-state
```

## Environment-Specific Deployments

### Development

```bash
terraform workspace select dev
terraform apply -var="environment=dev"
```

### Production

```bash
terraform workspace select prod
terraform apply -var="environment=prod" -var="asg_min_size=3" -var="asg_max_size=10"
```

## Security Considerations

1. **Never commit** `terraform.tfvars` with real passwords
2. **Use AWS Secrets Manager** for production passwords
3. **Enable MFA** for AWS account
4. **Use IAM roles** with least privilege
5. **Enable CloudTrail** for audit logging

## Cost Monitoring

Monitor costs during and after deployment:

```bash
# Check current month costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

## Next Steps After Deployment

1. ✅ Verify application is accessible
2. ✅ Test database connectivity via `/api/db-test`
3. ✅ Test S3 connectivity via `/api/s3-test`
4. ✅ Configure SNS email alerts (optional)
5. ✅ Set up custom domain (optional)
6. ✅ Configure HTTPS certificate (optional)
7. ✅ Review CloudWatch alarms
8. ✅ Set up cost alerts in AWS Billing

---

For detailed architecture information, see [ARCHITECTURE.md](ARCHITECTURE.md)

