# UFW-Cloudflare

🌐 [English](README.md) | [Português](README.pt-BR.md) | **Español** | [中文](README.zh.md) | [Íslenska](README.is.md)

Gestiona automáticamente los [rangos de IP de Cloudflare](https://www.cloudflare.com/ips/) en UFW (Uncomplicated Firewall). Este script obtiene las direcciones IPv4 e IPv6 más recientes de Cloudflare y crea reglas de firewall para tráfico HTTP/HTTPS (puertos 80 y 443 TCP), asegurando que solo las solicitudes proxied por Cloudflare lleguen a tu servidor de origen.

Diseñado para **servidores Ubuntu** (también compatible con sistemas basados en Debian).

> **Prevención contra DDoS:** Al permitir solo los rangos de IP de Cloudflare y bloquear todo el tráfico directo en los puertos 80/443, tu servidor de origen se vuelve invisible para los atacantes. Todas las solicitudes HTTP/HTTPS deben pasar primero por la red de Cloudflare, aprovechando su mitigación de DDoS, WAF y protección contra bots antes de llegar a tu servidor. Los ataques DDoS directos al servidor de origen se bloquean efectivamente, ya que las IPs fuera de Cloudflare son denegadas a nivel de firewall.

## ¿Por qué?

Cuando tu dominio está proxied a través de Cloudflare, todo el tráfico de los visitantes llega desde las [direcciones IP de Cloudflare](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/) en lugar de las IPs individuales de los visitantes. Tu firewall debe permitir estos rangos, de lo contrario el tráfico legítimo será bloqueado. Sin esta configuración, la IP de tu servidor de origen puede quedar expuesta y vulnerable a ataques DDoS directos que evitan Cloudflare. Este script automatiza ese proceso y mantiene las reglas actualizadas.

## Requisitos

- **Ubuntu 20.04+** (o sistema basado en Debian)
- `ufw` instalado y habilitado
- `wget`
- Privilegios root (`sudo`)

## Inicio Rápido

```bash
wget -O ufw.sh https://raw.githubusercontent.com/hyzis-manager/ufw-cloudflare/main/ufw.sh
chmod +x ufw.sh
sudo ./ufw.sh
```

En la primera ejecución, el script:

1. Garantiza que el **SSH siga permitido** (puerto **2233/tcp** por defecto) — protección contra bloqueo al habilitar el firewall
2. Obtiene los rangos IPv4 e IPv6 actuales de Cloudflare desde `cloudflare.com/ips-v4` y `cloudflare.com/ips-v6`
3. Crea reglas de permiso en UFW para cada rango en los puertos **80** y **443** (TCP)
4. Pregunta si deseas activar **Supervision** (actualización automática diaria)

## Uso

```
sudo ./ufw.sh [opciones]
```

| Opción | Corto | Descripción |
|---|---|---|
| `--help` | `-h` | Muestra el mensaje de ayuda |
| `--purge` | `-p` | Elimina todas las reglas existentes de Cloudflare (marcadas con comentario `#cloudflare`) antes de agregar nuevas |
| `--no-new` | `-n` | No obtiene IPs ni agrega nuevas reglas (usar con `--purge` para solo eliminar reglas) |
| `--supervision` | `-s` | Activa actualización automática diaria mediante timer de systemd |

## Ejemplos

**Primera configuración** — obtener y permitir todas las IPs de Cloudflare:

```bash
sudo ./ufw.sh
```

**Actualizar reglas** — eliminar reglas antiguas y agregar las actuales:

```bash
sudo ./ufw.sh --purge
```

**Eliminar todas las reglas de Cloudflare** sin agregar nuevas:

```bash
sudo ./ufw.sh --purge --no-new
```

**Activar actualización automática diaria** (Supervision):

```bash
sudo ./ufw.sh --supervision
```

## Puerto SSH (por defecto)

Cada vez que se ejecuta — incluidas las actualizaciones automáticas de **Supervision** — el script garantiza que el **SSH siga permitido**, para que nunca te bloquees a ti mismo al habilitar/restringir el firewall. Por defecto permite el puerto **2233/tcp** desde cualquier origen, con el comentario `cf-ufw-ssh`.

Esta regla es **independiente de las reglas de Cloudflare**: `--purge` (que solo elimina reglas con el comentario `# cloudflare`) **no** la elimina.

Para usar otro(s) puerto(s), define la variable `CFUFW_SSH_PORTS` (lista separada por espacios):

```bash
# Puerto SSH estándar (22) en lugar del personalizado
sudo CFUFW_SSH_PORTS="22" ./ufw.sh

# Mantener ambos durante una migración de puerto
sudo CFUFW_SSH_PORTS="22 2233" ./ufw.sh
```

## Supervision

La función Supervision instala un **timer de systemd** que ejecuta el script una vez cada 24 horas con `--purge`, asegurando que tus reglas de firewall siempre reflejen los rangos de IP más recientes de Cloudflare.

Cuando se activa, se crean dos unidades de systemd:

- `ufw-cloudflare-supervision.service` — servicio oneshot que ejecuta el script
- `ufw-cloudflare-supervision.timer` — timer que dispara el servicio diariamente (y 5 minutos después del arranque)

### Gestión del timer

```bash
# Verificar estado del timer
systemctl status ufw-cloudflare-supervision.timer

# Ver próxima ejecución programada
systemctl list-timers ufw-cloudflare-supervision.timer

# Desactivar actualizaciones automáticas
sudo systemctl stop ufw-cloudflare-supervision.timer
sudo systemctl disable ufw-cloudflare-supervision.timer

# Disparar una actualización manualmente
sudo systemctl start ufw-cloudflare-supervision.service
```

## Cómo Funciona

1. Garantiza primero la regla de SSH: `ufw allow 2233/tcp comment "cf-ufw-ssh"` (siempre, incluso con `--purge` o `--no-new`)
2. Obtiene los rangos IPv4 de `https://www.cloudflare.com/ips-v4`
3. Obtiene los rangos IPv6 de `https://www.cloudflare.com/ips-v6`
4. Para cada rango CIDR, ejecuta: `ufw allow from <IP> to any port 80,443 proto tcp comment "cloudflare"`
5. Cuando se usa `--purge`, elimina todas las reglas UFW marcadas con el comentario `# cloudflare` antes de agregar nuevas (la regla SSH `cf-ufw-ssh` se conserva)
6. Valida los formatos de IP y verifica que la descarga fue exitosa antes de aplicar cambios

## Leyenda de Salida

Durante la ejecución, el script muestra indicadores de progreso:

- **`+`** (verde) — regla creada
- **`-`** (rojo) — regla eliminada
- **`.`** (gris) — regla omitida (ya existe o es inválida)

## Rangos de IP de Cloudflare

El script obtiene las IPs directamente de los endpoints oficiales de Cloudflare. Estos rangos también están disponibles a través de la [API de Cloudflare](https://developers.cloudflare.com/api/resources/ips/methods/list/) en `https://api.cloudflare.com/client/v4/ips` (sin necesidad de autenticación). Cloudflare actualiza estos rangos con poca frecuencia, pero recomienda mantener tu allowlist actualizada.

## Licencia

MIT
