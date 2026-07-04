# UFW-Cloudflare

🌐 [English](README.md) | [Português](README.pt-BR.md) | [Español](README.es.md) | [中文](README.zh.md) | **Íslenska**

Stjórnar sjálfkrafa [IP-sviðum Cloudflare](https://www.cloudflare.com/ips/) í UFW (Uncomplicated Firewall). Þetta skrifta sækir nýjustu IPv4 og IPv6 vistföng Cloudflare og býr til eldveggsreglur fyrir HTTP/HTTPS umferð (gáttir 80 og 443 TCP), sem tryggir að aðeins beiðnir sem fara í gegnum Cloudflare nái til upprunaþjónsins þíns.

Hannað fyrir **Ubuntu þjóna** (einnig samhæft við Debian-byggð kerfi).

> **DDoS vörn:** Með því að leyfa aðeins IP-svið Cloudflare og loka allri annarri beinni umferð á gáttum 80/443 verður upprunaþjónninn þinn ósýnilegur árásarmönnum. Allar HTTP/HTTPS beiðnir verða að fara fyrst í gegnum net Cloudflare, sem nýtir innbyggða DDoS-vörn, WAF og vélmennavörn áður en þær ná til þjónsins þíns. Beinar DDoS-árásir á upprunaþjóninn eru í raun útilokaðar þar sem IP-vistföng utan Cloudflare er hafnað á eldveggsstigi.

## Af hverju?

Þegar lénið þitt er sett í gegnum Cloudflare kemur öll umferð gestanna frá [IP-vistföngum Cloudflare](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/) í stað einstakra IP-vistfanga gestanna. Eldveggurinn þinn verður að leyfa þessi svið, annars verður lögmæt umferð stöðvuð. Án þessarar stillingar gæti IP-vistfang upprunaþjónsins þíns verið útsett og viðkvæmt fyrir beinum DDoS-árásum sem fara framhjá Cloudflare. Þetta skrifta sjálfvirknivæðir þetta ferli og heldur reglunum uppfærðum.

## Kröfur

- **Ubuntu 20.04+** (eða Debian-byggt kerfi)
- `ufw` uppsett og virkt
- `wget`
- Root réttindi (`sudo`)

## Fljótleg Byrjun

```bash
wget -O ufw.sh https://raw.githubusercontent.com/hyzis-manager/ufw-cloudflare/main/ufw.sh
chmod +x ufw.sh
sudo ./ufw.sh
```

Í fyrstu keyrslu mun skriftað:

1. Tryggja að **SSH haldist opið** (gátt **2233/tcp** sjálfgefið) — vörn gegn því að læsa þig úti þegar eldveggurinn er virkjaður
2. Sækja núverandi IPv4 og IPv6 svið Cloudflare frá `cloudflare.com/ips-v4` og `cloudflare.com/ips-v6`
3. Búa til UFW leyfisreglur fyrir hvert svið á gáttum **80** og **443** (TCP)
4. Spyrja hvort þú viljir virkja **Supervision** (sjálfvirka daglega uppfærslu)

## Notkun

```
sudo ./ufw.sh [valkostir]
```

| Valkostur | Stutt | Lýsing |
|---|---|---|
| `--help` | `-h` | Sýna hjálparskilaboð |
| `--purge` | `-p` | Eyða öllum núverandi Cloudflare reglum (merktar með `#cloudflare` athugasemd) áður en nýjar eru bættar við |
| `--no-new` | `-n` | Ekki sækja IP-vistföng né bæta við nýjum reglum (nota með `--purge` til að aðeins eyða reglum) |
| `--supervision` | `-s` | Virkja sjálfvirka daglega uppfærslu með systemd tímamæli |

## Dæmi

**Fyrsta uppsetning** — sækja og leyfa öll Cloudflare IP-vistföng:

```bash
sudo ./ufw.sh
```

**Uppfæra reglur** — eyða gömlum reglum og bæta við núverandi:

```bash
sudo ./ufw.sh --purge
```

**Eyða öllum Cloudflare reglum** án þess að bæta við nýjum:

```bash
sudo ./ufw.sh --purge --no-new
```

**Virkja sjálfvirka daglega uppfærslu** (Supervision):

```bash
sudo ./ufw.sh --supervision
```

## SSH gátt (sjálfgefið)

Í hvert sinn sem það keyrir — þar á meðal sjálfvirku **Supervision** uppfærslurnar — tryggir skriftað að **SSH haldist opið**, svo þú getir aldrei læst þig úti þegar þú virkjar/hertir eldvegginn. Sjálfgefið leyfir það gátt **2233/tcp** frá hvaða uppruna sem er, merkt með `cf-ufw-ssh` athugasemd.

Þessi regla er **óháð Cloudflare reglunum**: `--purge` (sem eyðir aðeins reglum merktum `# cloudflare`) eyðir henni **ekki**.

Til að nota aðra gátt/gáttir, stilltu breytuna `CFUFW_SSH_PORTS` (listi aðskilinn með bilum):

```bash
# Venjuleg SSH gátt (22) í stað sérsniðnu
sudo CFUFW_SSH_PORTS="22" ./ufw.sh

# Halda báðum meðan á gáttarflutningi stendur
sudo CFUFW_SSH_PORTS="22 2233" ./ufw.sh
```

## Supervision

Supervision eiginleikinn setur upp **systemd tímamæli** sem keyrir skriftað einu sinni á 24 klukkustunda fresti með `--purge`, sem tryggir að eldveggsreglurnar þínar endurspegli alltaf nýjustu IP-svið Cloudflare.

Þegar virkjað eru tvær systemd einingar búnar til:

- `ufw-cloudflare-supervision.service` — oneshot þjónusta sem keyrir skriftað
- `ufw-cloudflare-supervision.timer` — tímamæli sem ræsir þjónustuna daglega (og 5 mínútum eftir ræsingu)

### Stjórnun tímamælis

```bash
# Athuga stöðu tímamælis
systemctl status ufw-cloudflare-supervision.timer

# Sjá næstu áætlaða keyrslu
systemctl list-timers ufw-cloudflare-supervision.timer

# Slökkva á sjálfvirkum uppfærslum
sudo systemctl stop ufw-cloudflare-supervision.timer
sudo systemctl disable ufw-cloudflare-supervision.timer

# Ræsa uppfærslu handvirkt
sudo systemctl start ufw-cloudflare-supervision.service
```

## Hvernig Það Virkar

1. Tryggir SSH regluna fyrst: `ufw allow 2233/tcp comment "cf-ufw-ssh"` (alltaf, jafnvel með `--purge` eða `--no-new`)
2. Sækir IPv4 svið frá `https://www.cloudflare.com/ips-v4`
3. Sækir IPv6 svið frá `https://www.cloudflare.com/ips-v6`
4. Fyrir hvert CIDR svið keyrir: `ufw allow from <IP> to any port 80,443 proto tcp comment "cloudflare"`
5. Þegar `--purge` er notað eyðir öllum UFW reglum merktar með `# cloudflare` athugasemd áður en nýjar eru bættar við (SSH reglan `cf-ufw-ssh` er varðveitt)
6. Staðfestir IP-snið og sannreynir að niðurhal hafi tekist áður en breytingar eru settar í framkvæmd

## Útskýring Úttaks

Meðan á keyrslu stendur sýnir skriftað framvinduvísa:

- **`+`** (grænt) — regla búin til
- **`-`** (rautt) — regla eytt
- **`.`** (grátt) — regla sleppt (er þegar til eða ógild)

## IP-svið Cloudflare

Skriftað sækir IP-vistföng beint frá opinberum endapunktum Cloudflare. Þessi svið eru einnig tiltæk í gegnum [Cloudflare API](https://developers.cloudflare.com/api/resources/ips/methods/list/) á `https://api.cloudflare.com/client/v4/ips` (engin auðkenning nauðsynleg). Cloudflare uppfærir þessi svið sjaldan en mælir með því að halda leyfislistanum þínum uppfærðum.

## Leyfi

MIT
