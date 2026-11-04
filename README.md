# Jogokart — Protótipo Multiplayer 3D (Godot 4.7)

Protótipo inicial focado em **game feel arcade** (inspirado em *Mario Kart* e *Crash Team Racing*) e **multiplayer Web + Desktop** usando Godot 4.7 (GDScript + `gl_compatibility` + Jolt Physics).

## Controles

| Ação | Teclado | Controle (Gamepad) |
| :--- | :--- | :--- |
| **Acelerar** | `W` ou `↑` | `A` (Xbox) / `X` (PS) ou `RT` |
| **Frear / Ré** | `S` ou `↓` | `B` / `X` ou `LT` |
| **Virar** | `A` / `D` ou `←` / `→` | Analógico Esquerdo ou D-Pad |
| **Pulo (Hop) + Drift** | `Espaço` ou `Shift` | `RB` ou `LB` |
| **Reposicionar (Respawn)** | `R` | `Select` / `Back` |
| **Menu / Pausa** | `Esc` | `Start` |

### Como funciona o Drift + Mini-Turbo
1. Acelere e segure **Pulo/Drift** (`Espaço` ou `RB`) enquanto esterça para um lado.
2. Durante o drift, incline o volante **para dentro da curva** para fechar mais o raio e carregar a barra mais rápido, ou **para fora** para abrir a curva sem perder o drift.
3. Observe a cor das faíscas nos pneus traseiros:
   - **Azul**: Mini-Turbo (estágio 1)
   - **Laranja**: Super Turbo (estágio 2)
   - **Roxo**: Ultra Turbo (estágio 3)
4. Solte o botão de drift para disparar o turbo (com *kick* de velocidade, FOV dinâmico e chamas no escapamento).

---

## Arquitetura do Protótipo

- [`scripts/kart.gd`](scripts/kart.gd) + [`scenes/kart.tscn`](scenes/kart.tscn): Física *Sphere-Kart* (`RigidBody3D` esférico invisível) com decomposição ortogonal da velocidade nos eixos do kart (frente, lateral com *grip* exponencial diferenciado entre aderência normal e drift, e normal da rampa/pista) e *heading* independente. O modelo visual low-poly segue a esfera com interpolação de física, inclinação por molas (*roll* e *pitch*), *squash & stretch* no pulo/aterrissagem, contra-esterço visual e partículas de faísca/poeira/fogo.
- [`scripts/kart_camera.gd`](scripts/kart_camera.gd): Câmera de perseguição com atraso suave no ângulo (revela a lateral do kart no drift), FOV dinâmico por velocidade + *kick* no turbo e *screen shake* baseado em trauma.
- [`scripts/net.gd`](scripts/net.gd): Multiplayer via `WebSocketMultiplayerPeer` (porta `8080`), compatível com navegadores HTML5 e builds Windows, com autoridade por cliente no próprio kart (*zero input lag*) e *dead-reckoning* suave nos karts remotos. Aceita parâmetro `?server=wss://...` direto na URL do navegador.
- [`scripts/world.gd`](scripts/world.gd): Pista oval com zebras, linha de largada, cones físicos que voam na batida, rampas, *tabletop*, *boost pads* e árvores/pedras low-poly geradas proceduralmente.

---

## Como jogar online de graça com seu colega (Vercel + Cloudflare Tunnel)

Como navegadores Web rodam em `https://` na Vercel e não podem abrir portas de servidor diretamente, a arquitetura gratuita funciona assim:
- **O jogo Web estático** fica hospedado gratuitamente na **Vercel**.
- **Quem hospeda a partida (Host)** roda o jogo no PC (pelo Editor do Godot ou executável Windows) e abre um túnel seguro gratuito (`wss://`) com o script [`tools/host_online.ps1`](tools/host_online.ps1) (que usa o Cloudflare Quick Tunnel, sem precisar de conta nem abrir portas no roteador).

### Passo 1 — Hospedar a partida no seu PC
1. Abra o projeto no Godot 4.7, dê **Play (F5)** e clique em **Hospedar partida (porta 8080)**.
2. Em um terminal PowerShell na pasta `e:\jogokart\jogokart`, rode:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\host_online.ps1
   ```
   *(Ou adicione `-Headless` se quiser subir um servidor dedicado em segundo plano sem abrir janela).*
3. O terminal vai exibir um link parecido com:
   `https://random-words-here.trycloudflare.com`
4. Mande esse link para o seu colega! Ele pode colar direto no campo **Servidor** do menu (o jogo converte `https://` para `wss://` automaticamente) ou abrir:
   `https://SEU-PROJETO.vercel.app/?server=wss://random-words-here.trycloudflare.com`

### Passo 2 — Exportar para Web e publicar na Vercel
1. Exporte o build Web para a pasta `build/web`:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\export_web.ps1 -InstallTemplates
   ```
2. Suba o repositório para o GitHub (`git add . && git commit -m "Protótipo inicial" && git push`).
3. Na **Vercel**, importe o repositório do GitHub:
   - Se a pasta raiz do repositório for `jogokart`, o [`vercel.json`](vercel.json) já aponta automaticamente para `build/web` e configura os cabeçalhos CORS/COOP/COEP.

