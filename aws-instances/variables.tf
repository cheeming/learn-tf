variable "ss_password" {
  description = "The password for the Shadowsocks server"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.ss_password) > 0 && length(regexall("[\r\n]", var.ss_password)) == 0
    error_message = "The Shadowsocks password must be nonempty and contain no line breaks."
  }
}

variable "ss_domain_name" {
  description = "The domain name used for TLS"
  type        = string
  default     = "tmpsc.net"
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*$", var.ss_domain_name))
    error_message = "The TLS domain must be a hostname without whitespace or shell metacharacters."
  }
}

variable "ss_cert_file" {
  description = "The certificate file for the domain name"
  type        = string
  default     = "/etc/shadowsocks/tls/fullchain.cer"
  validation {
    condition     = can(regex("^/etc/shadowsocks/tls/[A-Za-z0-9_-][A-Za-z0-9_.-]*$", var.ss_cert_file))
    error_message = "Install the certificate directly under /etc/shadowsocks/tls/ with a simple filename."
  }
}

variable "ss_key_file" {
  description = "The key file for the domain name"
  type        = string
  default     = "/etc/shadowsocks/tls/private.key"
  validation {
    condition     = can(regex("^/etc/shadowsocks/tls/[A-Za-z0-9_-][A-Za-z0-9_.-]*$", var.ss_key_file))
    error_message = "Install the private key directly under /etc/shadowsocks/tls/ with a simple filename."
  }
}

variable "noip_username" {
  description = "The username for No-IP"
  type        = string
}

variable "noip_password" {
  description = "The password for No-IP"
  type        = string
  sensitive   = true
}
