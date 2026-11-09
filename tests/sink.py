# Minimal SMTP sink for tests: accepts everything, no TLS, prints each message
# to stdout between markers so the test runner can read it back.
import asyncio


async def handle(reader, writer):
    async def send(line):
        writer.write((line + "\r\n").encode())
        await writer.drain()

    await send("220 sink ESMTP")
    data_mode = False
    buf = []
    while True:
        raw = await reader.readline()
        if not raw:
            break
        line = raw.decode(errors="replace").rstrip("\r\n")
        if data_mode:
            if line == ".":
                data_mode = False
                print("----- MESSAGE BEGIN -----")
                print("\n".join(buf))
                print("----- MESSAGE END -----", flush=True)
                buf = []
                await send("250 2.0.0 Ok: queued")
            else:
                buf.append(line[1:] if line.startswith("..") else line)
            continue
        cmd = line.split(" ", 1)[0].upper()
        if cmd in ("EHLO", "HELO"):
            await send("250-sink")
            await send("250 8BITMIME")
        elif cmd == "DATA":
            data_mode = True
            await send("354 go ahead")
        elif cmd == "QUIT":
            await send("221 bye")
            break
        elif cmd in ("MAIL", "RCPT", "RSET", "NOOP"):
            await send("250 Ok")
        else:
            await send("502 not implemented")
    writer.close()


async def main():
    server = await asyncio.start_server(handle, "0.0.0.0", 25)
    print("sink listening", flush=True)
    async with server:
        await server.serve_forever()


asyncio.run(main())
