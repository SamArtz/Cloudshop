# =============================================================================
# Amazon SES — Notificaciones (PDF secciones 3 y 9)
# =============================================================================

locals {
  ses_identity_arn = "arn:aws:ses:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:identity/${var.ses_sender_email}"
}

resource "aws_ses_email_identity" "sender" {
  count = var.ses_verify_sender ? 1 : 0
  email = var.ses_sender_email
}

# Nota (sandbox SES):
# - Debes verificar el remitente (este recurso envía el correo de verificación).
# - En sandbox también debes verificar cada destinatario, o salir del sandbox.
# - La Lambda notifications usa SES_FALLBACK_RECIPIENT = ses_sender_email si el
#   cliente no tiene un correo usable.
