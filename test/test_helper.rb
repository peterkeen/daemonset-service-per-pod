require 'rubygems'
require 'bundler'
Bundler.require(:default, :test)
require "webmock/minitest"

require_relative "../lib/startup.rb"

key = OpenSSL::PKey::RSA.new(1024)
public_key = key.public_key

subject = "/C=BE/O=Test/OU=Test/CN=Test"

cert = OpenSSL::X509::Certificate.new
cert.subject = cert.issuer = OpenSSL::X509::Name.parse(subject)
cert.not_before = Time.now
cert.not_after = Time.now + 365 * 24 * 60 * 60
cert.public_key = public_key
cert.serial = 0x0
cert.version = 2

ef = OpenSSL::X509::ExtensionFactory.new
ef.subject_certificate = cert
ef.issuer_certificate = cert
cert.extensions = [
  ef.create_extension("basicConstraints","CA:TRUE", true),
  ef.create_extension("subjectKeyIdentifier", "hash"),
  # ef.create_extension("keyUsage", "cRLSign,keyCertSign", true),
]
cert.add_extension ef.create_extension("authorityKeyIdentifier",
                                       "keyid:always,issuer:always")

cert.sign key, OpenSSL::Digest::SHA1.new

ENV['KUBE_TOKEN'] = Base64.strict_encode64("token")
ENV['KUBE_CA'] = Base64.strict_encode64(cert.to_pem)
ENV['KUBE_SERVER'] = "https://example.com:8443"

::Hook.mock!
