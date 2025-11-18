output "certificate_arn" {
  value = aws_acm_certificate_validation.validated.certificate_arn
}