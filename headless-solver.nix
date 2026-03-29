[Unit]
Description=SwagWatch Headless Solver (Scrapling + Camoufox)
After=network.target

[Service]
Type=simple
User=user
# Use the same directory as the rust engine
WorkingDirectory=/mnt/data/swagwatch-engine
# Use 'nix develop' to ensure the correct Python environment
ExecStart=nix develop --command python solver/main.py
Restart=always
RestartSec=5
# Ensure it listens on the port the engine expects
Environment=PORT=8000
Environment=SOLVER_URL=http://localhost:8000
Environment=VAULT_PATH==/mnt/data/swagwatch-engine/vault

[Install]
WantedBy=multi-user.target
