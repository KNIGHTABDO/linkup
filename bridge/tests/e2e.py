"""End-to-end check against a running bridge: python tests/e2e.py <port> <home> <agent> <model> "<prompt>" """
import asyncio, json, sys, collections, aiohttp

async def main(port, home, agent, model, prompt):
    token = open(f"{home}/token").read().strip()
    async with aiohttp.ClientSession() as http:
        async with http.ws_connect(f"http://127.0.0.1:{port}/linkup/ws?token={token}") as ws:
            async def call(op, **kw):
                await ws.send_json({"op": op, "rid": op, **kw})
            await call("catalog")
            await call("create", agent=agent, model=model, cwd="/tmp/linkup-e2e")
            counts = collections.Counter(); sid = None; text = []; first = {}
            async for m in ws:
                d = json.loads(m.data)
                if d["op"] == "catalog":
                    for a in d["agents"]:
                        print("catalog:", a["id"], a.get("available"), len(a.get("models") or []), "models", (a.get("error") or "")[:80])
                elif d["op"] == "session" and sid is None:
                    sid = d["session"]["id"]
                    await call("send", session=sid, text=prompt)
                elif d["op"] == "event":
                    e = d["event"]; counts[e["type"]] += 1
                    if e["type"] not in first:
                        first[e["type"]] = 1; print("  first", e["type"], json.dumps({k: v for k, v in e.items() if k not in ("ts",)})[:220])
                    if e["type"] == "text.delta": text.append(e["text"])
                    if e["type"] == "turn.end":
                        break
                elif d["op"] == "error":
                    print("ERROR", d)
            print("counts:", dict(counts)); print("text:", "".join(text)[:300])

asyncio.run(main(*sys.argv[1:6]))
