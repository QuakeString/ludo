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
image, `ghcr.io/quakestring/ludo-server:latest`. To use it instead of building
on the VPS, run `docker compose pull && docker compose up -d`. The first time,
make the package public on GitHub (your profile → Packages → ludo-server →
Package settings → Change visibility), or run `docker login ghcr.io` on the
VPS.

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
