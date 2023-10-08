output "argocd_pwd" {
  description = "Password of argocd"
  value = random_password.argocd
}