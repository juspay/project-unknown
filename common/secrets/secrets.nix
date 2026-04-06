let
  shivaraj = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFN5Ov2zDIG59/DaYKjT0sMWIY15er1DZCT9SIak07vK";
  admins = [ shivaraj ];

  idliv2-01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKfcMbXMuz8WYw/2GDjcgJnsl5s9SjwnAdK8CHr7aCyk";
in
{
  "netrc-juspay.age".publicKeys = admins ++ [ idliv2-01 ];
}
