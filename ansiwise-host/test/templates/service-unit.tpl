[Unit]
Description=A service of this machine that starts detached work
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=<command>
WorkingDirectory=<working-directory>
Restart=always
RestartSec=5
# A restart of this unit must not take the detached processes it started.
KillMode=process

[Install]
WantedBy=multi-user.target
