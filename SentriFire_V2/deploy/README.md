# Raspberry Pi deployment notes

Run `install_pi.sh` from the unpacked project. It creates a dedicated `sentrifire` service account, installs Python dependencies, downloads MediaMTX v1.20.1 from the official release, verifies its published checksum, and installs but does not immediately enable the services.

After editing the two secret configuration files, `enable_services.sh` validates placeholders, restricts file permissions, and starts both services at boot.

Useful commands:

```bash
sudo systemctl status mediamtx sentrifire-api
sudo journalctl -u mediamtx -u sentrifire-api -f
curl http://127.0.0.1:8000/health
ffprobe rtsp://127.0.0.1:8554/cam1
```

If the Pi cannot sustain three 640-pixel PyTorch inference passes with acceptable latency and temperature, follow the NCNN benchmark recommendation in `../docs/MODEL_AND_CALIBRATION.md`. Do not lower image size or skip frames without re-running site recall tests.

