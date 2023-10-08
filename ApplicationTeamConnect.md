# Connect with teams
https://catalog.us-east-1.prod.workshops.aws/workshops/d2b662ae-e9d7-4b31-b68b-64ade19d5dcc/en-US/030-provision-eks-cluster/03-team-management/3-connect-with-teams

## 1. Connect to the cluster as Team Riker
```bash
# Apply changes to provision the Platform Team
terraform output

```

Connect
```bash
aws eks --region eu-west-1 update-kubeconfig --name eks-blueprint-blue  --role-arn arn:aws:iam::798082067117:role/team-riker-20230531130037207700000002
```

You can also see which entity can execute the previous command by looking at the Trust Relationship of the team-riker role:
```bash
aws iam get-role --role-name team-riker-20230531130037207700000002
```

Now you can execute kubectl CLI commands in the team-riker namespace.

Let's see if we can do the same commands as previously:

```bash
# list nodes ? yes
kubectl get nodes
# List pods in team-riker namespace ? yes
kubectl get pods -n team-riker
# list all pods in all namespaces ? no
kubectl get pods -A
# can i create pods in kube-system namespace ? no
kubectl auth can-i create pods --namespace kube-system
# list service accounts in team-riker namespace ? yes
kubectl get sa -n team-riker
# list service accounts in default namespace ? no
kubectl get sa -n default
# can i create pods in team-riker namespace ? no (readonly)
kubectl auth can-i create pods --namespace team-riker
# can i list pods in team-riker namespace ? yes
kubectl auth can-i list pods --namespace team-riker

```

```bash
kubectl get resourcequotas -n team-riker

```
