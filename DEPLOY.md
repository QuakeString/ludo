# Running the game server on your own VPS

The server is one small Docker container (a few MB, a few tens of MB of RAM).
Everything it remembers, meaning players, friends and match history, is kept
in one JSON file on a Docker volume.

## 1. Start it

On the VPS, with Docker and the Compose plugin installed:

```sh
git clone https://github.com/QuakeString/ludo.git
cd ludo
git checkout claude/ludo-board-game-design-qd5nm3
docker compose up -d --build
```

Check that it answers:

```sh
curl http://localhost:8091/health      # → ok
```

Open port **8091** in the VPS firewall (and in your provider's firewall panel
if it has one).

In the app, choose **Play with friends** or **Online**, tap **Enter address**
and type the VPS's IP address, e.g. `203.0.113.7`. The app remembers it.

## 2. Optional: HTTPS with a domain

With a domain (or subdomain) pointing at the VPS, Caddy can put HTTPS in
front and fetch the certificate by itself:

```sh
echo "LUDO_DOMAIN=ludo.example.com" > .env
docker compose --profile https up -d --build
```

Open ports **80** and **443**. In the app, enter `ludo.example.com` as the
address. Invite links are then `https://ludo.example.com/r/CODE`.

## Updating

```sh
cd ludo
git pull
docker compose up -d --build
```

Players and their progress live on the `ludo-data` volume and survive this.

Every server change pushed to the main branch also publishes a ready-built
image, so the VPS never has to build. It goes to
`ghcr.io/quakestring/ludo-server:latest`, and to Docker Hub as
`quakestring/ludo-time-server:latest` once the repository has a
`DOCKERHUB_TOKEN` secret (a Docker Hub access token for the `quakestring`
account; GitHub → the repo → Settings → Secrets and variables → Actions).

The image also carries the browser version of the game. Open
`http://YOUR_IP:8091/` in any browser and it plays online against this
server straight away, with no address to type. Invite links offer "Play in
the browser" too, so a friend without the Android app can join from a laptop
or an iPhone.

Without the repository on the VPS at all:

```sh
docker run -d --name ludo-server -p 8091:8091 -v ludo-data:/data \
  --restart unless-stopped quakestring/ludo-time-server:latest
```

and to upgrade, `docker pull quakestring/ludo-time-server:latest`, then
`docker rm -f ludo-server` and the same `docker run` again.

## Useful commands

```sh
docker compose logs -f server          # what the server is doing
docker compose restart server
docker compose down                    # stop (data is kept)
```

Back up the data:

```sh
docker compose cp server:/data/players.json ./players-backup.json
```
