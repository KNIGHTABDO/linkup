"""python -m linkup_bridge [serve | pair | token]"""
import os
import sys

from .server import PORT, load_token, main

PUBLIC = os.environ.get("LINKUP_PUBLIC_URL", "https://desktop-1rsqaqq.tail7d75d9.ts.net")


def pair():
    import urllib.parse
    token = load_token()
    link = "linkup://pair?" + urllib.parse.urlencode({"url": PUBLIC, "token": token})
    print(f"Server:  {PUBLIC}\nToken:   {token}\nLink:    {link}\n")
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(link)
        qr.print_ascii(invert=True)
        print("Scan with the iPhone camera (or Linkup > Settings > Connect).")
    except ImportError:
        pass


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if cmd == "pair":
        pair()
    elif cmd == "token":
        print(load_token())
    else:
        main()
