#get ghe password
ARGOCD_PWD=$(aws secretsmanager get-secret-value --secret-id argocd-admin-secret.eks-blueprint | jq -r '.SecretString')
echo export ARGOCD_PWD=\"$ARGOCD_PWD\" >> ~/.bashrc
echo "ArgoCD admin password: $ARGOCD_PWD"


#access argocd UI if any 
kubectl port-forward svc/argo-cd-argocd-server 8080:443 -n argocd