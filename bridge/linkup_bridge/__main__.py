"""python -m linkup_bridge [serve | pair | token]"""
import json
import os
import subprocess
import sys

from .server import PORT, load_token, main


def get_public_url() -> str:
    if os.environ.get("LINKUP_PUBLIC_URL"):
        return os.environ["LINKUP_PUBLIC_URL"].rstrip("/")
    try:
        proc = subprocess.run(["tailscale", "status", "--json"], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0:
            data = json.loads(proc.stdout)
            dns = data.get("Self", {}).get("DNSName", "").rstrip(".")
            if dns:
                return f"https://{dns}"
    except Exception:
        pass
    return f"http://127.0.0.1:{PORT}"


def pair():
    import urllib.parse
    token = load_token()
    public_url = get_public_url()
    link = "linkup://pair?" + urllib.parse.urlencode({"url": public_url, "token": token})
    print(f"Server:  {public_url}\nToken:   {token}\nLink:    {link}\n")
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(link)
        qr.print_ascii(invert=True)
        print("Scan with the iPhone camera (or Linkup > Settings > Connect).")
    except ImportError:
        print("Tip: install 'qrcode' for ASCII QR code display: pip install qrcode")


def print_usage(file=sys.stderr):
    print("usage: python -m linkup_bridge [serve | pair | token]", file=file)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print_usage(sys.stdout)
        sys.exit(0)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if cmd == "serve":
        main()
    elif cmd == "pair":
        pair()
    elif cmd == "token":
        print(load_token())
    else:
        print_usage()
        sys.exit(2)
