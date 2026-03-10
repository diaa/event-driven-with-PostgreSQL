output "postgres_endpoint" {
  value = aws_db_instance.postgres.address
}

output "eks_name" {
  value = aws_eks_cluster.eks.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}
