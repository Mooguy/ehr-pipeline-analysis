# Common Commands

Quick reference for recurring commands in this project. Run from
`~/aidoc-ehr-pipeline` with the venv activated unless noted otherwise.

## Environment

```bash
source venv/bin/activate
```

## RDS — start / stop / status

```bash
aws rds start-db-instance --db-instance-identifier aidoc-ehr-pipeline
aws rds stop-db-instance --db-instance-identifier aidoc-ehr-pipeline
aws rds describe-db-instances --db-instance-identifier aidoc-ehr-pipeline \
  --query 'DBInstances[0].DBInstanceStatus' --output text
```

Always stop RDS when done for the session — it bills hourly while running.

## Fixing "connection timeout" (your IP changed)

Home IPs are dynamic and change periodically, which breaks the RDS security
group's allow-list. If pgAdmin/psql times out:

```bash
# 1. Check your current IP
curl -s https://checkip.amazonaws.com

# 2. Find the security group ID (only needed once, or if you forget it)
aws rds describe-db-instances --db-instance-identifier aidoc-ehr-pipeline \
  --query 'DBInstances[0].VpcSecurityGroups[*].VpcSecurityGroupId' --output text

# 3. Check the currently allowed IP(s)
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions[*].[FromPort,ToPort,IpRanges[*].CidrIp]' --output text

# 4. Swap old IP for new IP (replace both placeholders)
aws ec2 revoke-security-group-ingress --group-id <sg-id> --protocol tcp --port 5432 --cidr <OLD_IP>/32
aws ec2 authorize-security-group-ingress --group-id <sg-id> --protocol tcp --port 5432 --cidr <NEW_IP>/32
```

Current security group ID: `sg-0c2b9eace1eda16d6`

If pgAdmin still times out after the IP is confirmed correct (test with
`psql` below first to isolate it), delete and recreate the saved server
entry in pgAdmin — it can hold a stale connection state.

## Connect via psql (bypasses pgAdmin entirely)

```bash
psql -h aidoc-ehr-pipeline.c0rumk4uq6lj.us-east-1.rds.amazonaws.com -U ehradmin -d aidoc_ehr
```

## Run the ETL (safe to re-run — uses ON CONFLICT DO NOTHING)

```bash
python3 etl_fhir_to_postgres.py
```

## Cost check

```bash
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null]'   # idle Elastic IPs
aws ec2 describe-nat-gateways --filter Name=state,Values=available    # running NAT Gateways
```

Or check Cost Explorer in the AWS Console (Billing and Cost Management →
Cost Explorer, group by Service).

## Git workflow

```bash
git status
git add <files>
git commit -m "message"
git push
```

If push fails with "no upstream branch":
```bash
git push --set-upstream origin main
```
