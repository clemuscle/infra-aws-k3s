output "public_ip" {
  value = aws_instance.k3s.public_ip
}

output "ssh" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.k3s.public_ip}"
}

output "app_url" {
  value = "http://${aws_instance.k3s.public_ip}:30080"
}