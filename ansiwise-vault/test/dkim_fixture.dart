/// A key pair made for these tests and used nowhere else, in the two containers a private key
/// stands in, and the `p=` value `openssl pkey -pubout -outform DER | base64` prints for it.
///
/// **The known answer comes from outside this repository.** The public half was produced by openssl
/// and not by the code under test, so an error in reading the container turns the cases red rather
/// than being copied into the expectation.
library;

/// The private key as `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048` writes it.
const String pkcs8Fixture = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDvXK/KIuyoyQ98
xqCcon5MQ26scVHjYzVWsQby6x7dn+kFecnsxFTF8/sCOGnN5RkiQ+ruHX4zE2r1
EwhhZlhOFMjRo+XEicXJgl4JdNaUEmnXGV9HF1FdZSepJ2b/xIoknJe75AjEA7sE
UCKydeEtMCb6QA1iEzpwTNKENOH/xYBSyq+nSkYJLLw4KQCTSfNugpqpjZ9A4NEz
S2qoD8GPmTjy5XrRUVAPrqhTZgi3G9BViSikpYimDVxFMvR1pASejJdrFM710uvF
8swgO7Xt/UUAN2wnnYQofj8UXX1UlU3CYkDPyndzKKdB9ni8S2wJg4l6yJNEAsNs
Qvu9pV2ZAgMBAAECgf8+x3dbf013yOceQV838+pepcVjOujoHbJ1AKfXvTQm4Pa7
EiTaMLuHZh8j9AER7hIzNiTOx21+tf/dWslONt0FrSvvFfRtjjjrMqkWYV4ckywj
uKTWIXgBUoxvlRpo1+88vmjm0T+SljlZu6MgAL9C2th1iGLTa6ggY2qdLty6g+fo
gtJoqGMM+KN+yWhIrG9rKMHkxTIjQrVMbB/87lNVQHQYjPIPlpcPs5p8Xgclycnr
usvFem8Ztw7qPbc5v+d6TZKrHn354Y33TnMjV7CPN9E9nu+F7yPYn5qfLst/T2Dr
iurDoz2mZyIAME81Zv02xmUGEWdR5bwCYcQHrEECgYEA+tThdCMmjLdZKFaa20QI
/BFE/xS4lYAsZ1qICb4BBMG/HZ4/9Ej80y4oFSxP8klaA4lgXfmiQid2upV3H690
eTNquI5AE+jFE7l1lwojk0AKbEsLQBfNLJpvGUjeZ5i87/CZgxSDCrXws4YoE/Fh
Y6LigV3NGiI11HfYjNVOyCECgYEA9EtOHR4yxX5xxrqzohRlpr5sGsJG4DiupXgj
mDGQTPC898cDIBa+jWj6UhWbetwaI6KGW7+3ibm5PHi5OWOe6v7krJGT6MIXomMm
yhR9IrxHxgDwsRKmYvbMpOczUlbXbKBCYvaK9y55ZNX9y1jo/XkA3A14Pa7DR/wW
t9u4BnkCgYEAmf0bNBtoTTc6iyMwCrCn+2f2vcrQzydTG1he7+wv3+W6GMrQZH5y
iItrnCQKKKqTklxCRy88R/TGVSHxcghbLxU7zXW3LQHYC5Xt9P4KfRnxzC3+CCkU
ku90iUdNEriYNY22EN0E3gx4ax5PeH7V1T9oYxddFVAvT/MLhNpndUECgYEAmDkY
apJ3ppJ8yQ1rg5JcKQO9DwuB6JPJV7g9zccMmLTluyuaKfOiNzFz0ZQ/NtZRv2S1
fhQ/hKVi5GiBWl5WFy5PRazM0pum6HwKHp+Xvf4+ZwYM9PmfDkmlCRg75ZHRWJGf
7FSeERo3cHrbU0uKmu88duI5y43Lh15wtY5G5FkCgYEAxISTkcGC5i689Y0gotYO
F6XTn2wuTpvx7Xk2Cx1rNXQWfgLkaIuMmpYuenLIMWQMvW5broqC1V7ZeLwpDfQm
afa/FxJ9/tQx5W5ftW70RCWKjAjG0LgOQH3D9gB5ePaz4wmhEknWjWU1lHJpZB7z
VpGXds4OaKTfh43fwN+xTD8=
-----END PRIVATE KEY-----
''';

/// The same key as `openssl rsa -traditional` writes it.
const String pkcs1Fixture = '''
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA71yvyiLsqMkPfMagnKJ+TENurHFR42M1VrEG8use3Z/pBXnJ
7MRUxfP7AjhpzeUZIkPq7h1+MxNq9RMIYWZYThTI0aPlxInFyYJeCXTWlBJp1xlf
RxdRXWUnqSdm/8SKJJyXu+QIxAO7BFAisnXhLTAm+kANYhM6cEzShDTh/8WAUsqv
p0pGCSy8OCkAk0nzboKaqY2fQODRM0tqqA/Bj5k48uV60VFQD66oU2YItxvQVYko
pKWIpg1cRTL0daQEnoyXaxTO9dLrxfLMIDu17f1FADdsJ52EKH4/FF19VJVNwmJA
z8p3cyinQfZ4vEtsCYOJesiTRALDbEL7vaVdmQIDAQABAoH/Psd3W39Nd8jnHkFf
N/PqXqXFYzro6B2ydQCn1700JuD2uxIk2jC7h2YfI/QBEe4SMzYkzsdtfrX/3VrJ
TjbdBa0r7xX0bY446zKpFmFeHJMsI7ik1iF4AVKMb5UaaNfvPL5o5tE/kpY5Wbuj
IAC/QtrYdYhi02uoIGNqnS7cuoPn6ILSaKhjDPijfsloSKxvayjB5MUyI0K1TGwf
/O5TVUB0GIzyD5aXD7OafF4HJcnJ67rLxXpvGbcO6j23Ob/nek2Sqx59+eGN905z
I1ewjzfRPZ7vhe8j2J+any7Lf09g64rqw6M9pmciADBPNWb9NsZlBhFnUeW8AmHE
B6xBAoGBAPrU4XQjJoy3WShWmttECPwRRP8UuJWALGdaiAm+AQTBvx2eP/RI/NMu
KBUsT/JJWgOJYF35okIndrqVdx+vdHkzariOQBPoxRO5dZcKI5NACmxLC0AXzSya
bxlI3meYvO/wmYMUgwq18LOGKBPxYWOi4oFdzRoiNdR32IzVTsghAoGBAPRLTh0e
MsV+cca6s6IUZaa+bBrCRuA4rqV4I5gxkEzwvPfHAyAWvo1o+lIVm3rcGiOihlu/
t4m5uTx4uTljnur+5KyRk+jCF6JjJsoUfSK8R8YA8LESpmL2zKTnM1JW12ygQmL2
ivcueWTV/ctY6P15ANwNeD2uw0f8FrfbuAZ5AoGBAJn9GzQbaE03OosjMAqwp/tn
9r3K0M8nUxtYXu/sL9/luhjK0GR+coiLa5wkCiiqk5JcQkcvPEf0xlUh8XIIWy8V
O811ty0B2AuV7fT+Cn0Z8cwt/ggpFJLvdIlHTRK4mDWNthDdBN4MeGseT3h+1dU/
aGMXXRVQL0/zC4TaZ3VBAoGBAJg5GGqSd6aSfMkNa4OSXCkDvQ8LgeiTyVe4Pc3H
DJi05bsrminzojcxc9GUPzbWUb9ktX4UP4SlYuRogVpeVhcuT0WszNKbpuh8Ch6f
l73+PmcGDPT5nw5JpQkYO+WR0ViRn+xUnhEaN3B621NLiprvPHbiOcuNy4decLWO
RuRZAoGBAMSEk5HBguYuvPWNIKLWDhel059sLk6b8e15NgsdazV0Fn4C5GiLjJqW
LnpyyDFkDL1uW66KgtVe2Xi8KQ30Jmn2vxcSff7UMeVuX7Vu9EQliowIxtC4DkB9
w/YAeXj2s+MJoRJJ1o1lNZRyaWQe81aRl3bODmik34eN38DfsUw/
-----END RSA PRIVATE KEY-----
''';

/// What `openssl pkey -pubout -outform DER | base64 -w0` prints for the key above.
const String publicKeyFixture =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA71yvyiLsqMkPfMagnKJ+TENurHFR42M1VrEG8use3Z/'
    'pBXnJ7MRUxfP7AjhpzeUZIkPq7h1+MxNq9RMIYWZYThTI0aPlxInFyYJeCXTWlBJp1xlfRxdRXWUnqSdm/8SKJJyXu+'
    'QIxAO7BFAisnXhLTAm+kANYhM6cEzShDTh/8WAUsqvp0pGCSy8OCkAk0nzboKaqY2fQODRM0tqqA/Bj5k48uV60VFQD'
    '66oU2YItxvQVYkopKWIpg1cRTL0daQEnoyXaxTO9dLrxfLMIDu17f1FADdsJ52EKH4/FF19VJVNwmJAz8p3cyinQfZ4'
    'vEtsCYOJesiTRALDbEL7vaVdmQIDAQAB';

/// A private key of another algorithm in the same PKCS#8 container, which is not an RSA key and
/// must never be read as one.
const String ed25519Fixture = '''
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIOpEr0vFSm2PVSfvlaUZDDhtq67YIbfEAlq6K4DL/VF4
-----END PRIVATE KEY-----
''';
