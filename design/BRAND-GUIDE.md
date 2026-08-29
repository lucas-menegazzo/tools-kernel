# Devin / Cognition — Guia de Marca para Apresentações

Materiais extraídos de `devin.ai`, `cognition.com` e `old.cognition.ai/brand` em **29/08/2026**.
Tudo nesta pasta é reutilizável direto no PowerPoint / Google Slides / Figma.

---

## 1. Paleta oficial (página de marca da Cognition)

Estas são as **únicas 3 cores declaradas publicamente** como "Devin Color Palette":

| Nome oficial | HEX | RGB | Uso sugerido |
|---|---|---|---|
| Purple | `#3969CA` | 57, 105, 202 | Cor primária de destaque, títulos, gráficos |
| Green | `#21C19A` | 33, 193, 154 | Positivo, métricas de ganho, checks |
| Blue | `#0294DE` | 2, 148, 222 | Links, apoio, segunda série de gráfico |

> Observação: a Cognition chama `#3969CA` de "Purple", mas na prática é um azul-índigo.
> Mantive o nome oficial para você citar corretamente se alguém perguntar.

---

## 2. Design system real do site devin.ai (tema escuro)

O site é **dark-first**. Se o deck for escuro, use estes valores — é o visual real do produto.

### Fundos
| Token | HEX | Uso |
|---|---|---|
| `bg-page` | `#141414` | Fundo do slide |
| `bg-wash` | `#191919` | Seção alternada |
| `bg-elevated` | `#1F1F1F` | Cards, caixas |
| `bg-accent-neutral` | `#F9F9F9` | Bloco invertido (claro sobre escuro) |

### Texto (branco com opacidade)
| Token | Valor | Uso |
|---|---|---|
| `text-primary` | `#FFFFFF` @ 90% | Corpo e títulos |
| `text-secondary` | `#FFFFFF` @ 52% | Subtítulo, legenda |
| `text-muted` | `#FFFFFF` @ 40% | Rodapé, notas |
| `text-disabled` | `#FFFFFF` @ 40% | Desabilitado |
| `text-primary-strong` | `#FFFFFF` @ 100% | Números grandes, destaque |

### Acentos e cores semânticas
| Token | HEX | Uso |
|---|---|---|
| `text-accent-primary` | `#49B0FF` | Azul de destaque (o "azul do Devin") |
| `bg-accent-primary` | `#4489FF` | Botão primário |
| `text-link` / `text-link-strong` | `#3EB8ED` | Links |
| `text-green` | `#00EC7E` | Sucesso, ganho, "aprovado" |
| `text-red` / `destructive` | `#F53B3A` | Erro, risco, "antes" |
| `text-purple` | `#956CDE` | Categoria / série extra |
| `text-orange` | `#F58E3A` | Alerta, atenção |
| `text-blue` | `#337DF4` | Série de gráfico |
| `text-always-black` | `#0D0F0D` | Preto de marca |

### Bordas e tints (branco com opacidade — para separadores)
| Token | Valor |
|---|---|
| `border-primary` | `#FFFFFF` @ 8% |
| `border-secondary` | `#FFFFFF` @ 4% |
| `tint-primary` | `#FFFFFF` @ 8% |
| `tint-secondary` | `#FFFFFF` @ 5% |
| `tint-tertiary` | `#FFFFFF` @ 3% |
| `tint-faint` | `#FFFFFF` @ 1.5% |
| `bg-scrim` | `#000000` @ 32% |

### Sombras
```
L1  0px 1px 2px  rgba(0,0,0,.20)
L2  0px 1px 3px  rgba(0,0,0,.25) + 0px 1px 2px rgba(0,0,0,.06)
L3  0px 10px 15px -3px rgba(0,0,0,.30) + 0px 4px 6px -2px rgba(0,0,0,.05)
L4  0px 25px 50px -12px rgba(0,0,0,.50)
```

---

## 3. Cognition.com hoje (tema claro)

O site institucional da Cognition mudou para um visual **claro e editorial**, bem diferente do Devin.

| Item | Valor |
|---|---|
| Fundo | `#F7F6F5` (off-white quente) |
| Texto | `#000000` |
| Fonte de corpo | **STK Bureau Serif** (serifada) |
| Fonte de título | **NB International Pro** |
| Fonte mono | **Geist Mono** |

Headline atual: *"Cognition operates Devin, the first autonomous software engineer."*

### Cognition legado (old.cognition.ai) — paleta azul-acinzentada
| Token | HEX |
|---|---|
| dark-01 | `#0F131C` |
| dark-02 | `#1F283B` |
| dark-03 | `#364363` |
| light-01 | `#F2F5FA` |
| light-02 | `#EAF0F9` |
| grey-01 | `#CDD3E1` |
| grey-02 | `#7B8397` |
| accent-01 | `#9EAEE9` |
| accent-02 | `#A2D1CE` |
| error | `#FA5050` |

Gradientes legado:
```css
--color-gradient-01: linear-gradient(to right, #7485CA 0%, #81B7D4 46%, #85C4C0 100%);
--color-gradient-02: linear-gradient(to left,  #83BCCC 0%, #85C3C0 100%);
```

---

## 4. Tipografia

### Fontes reais usadas (arquivos em `assets/fonts/`)

| Fonte | Onde é usada | Licença |
|---|---|---|
| **NB International Pro** (Light 300, Regular 400) | Fonte principal do devin.ai + títulos do cognition.com | **Comercial (Neubau)** — precisa licença |
| **STK Bureau Serif** (Book, Medium) | Corpo do cognition.com | **Comercial** — precisa licença |
| **Geist Mono** (Regular + Variable) | Código/mono no devin.ai e cognition.com | **Grátis, OFL** (Vercel) |
| **Inter** | Fonte de apoio no devin.ai | **Grátis, OFL** |
| **IBM Plex Mono / Sans / Sans Condensed** | Site legado old.cognition.ai | **Grátis, OFL** (IBM) |
| **Merriweather** | Site legado (serifada) | **Grátis, OFL** |

> **Importante para o PPT:** NB International Pro e STK Bureau Serif são fontes **comerciais**.
> Os arquivos `.woff2` aqui são os subsets que os sites servem publicamente — servem como
> referência visual, mas **não instale nem distribua** num deck externo sem licença.

### Substitutas grátis (visualmente próximas) — use estas no PPT
| No lugar de | Use | Onde achar |
|---|---|---|
| NB International Pro | **Inter** (ou Helvetica Now / Arial) | Google Fonts — já está em `assets/fonts/` |
| STK Bureau Serif | **Source Serif 4** ou **Lora** | Google Fonts |
| Geist Mono | **Geist Mono** (já é grátis) ou **IBM Plex Mono** | Já está em `assets/fonts/` |

### Escala tipográfica fluida do devin.ai
```
--fluid-36-60   36px -> 60px    Hero / título de abertura
--fluid-36-50   36px -> 50px    Título de seção
--fluid-22-40   22px -> 40px    Subtítulo grande
--fluid-20-30   20px -> 30px    Título de card
--fluid-18-30   18px -> 30px    Destaque
--fluid-16-22   16px -> 22px    Lead / intro
--fluid-16-18   16px -> 18px    Corpo
--fluid-14-18   14px -> 18px    Corpo menor
--fluid-14-16   14px -> 16px    Legenda
--fluid-12-16   12px -> 16px    Nota de rodapé
```
Grid: 12 colunas, gutter 10px, padding lateral 20px.

---

## 5. Inventário de arquivos

```
assets/
├─ fonts/                       19 arquivos .woff2/.ttf (todas as fontes acima)
├─ logos/
│  ├─ devin-wordmark.svg        Logo Devin do header do site (SVG vetorial)
│  ├─ lockups/                  6 PNGs oficiais em altíssima resolução
│  │   Cognition_PrimaryLockup_Black.png    1440x600
│  │   Cognition_PrimaryLockup_White.png    1440x600
│  │   Devin_PrimaryLockup_Black.png        2554x1214
│  │   Devin_PrimaryLockup_White.png       10211x4854  <- melhor para slide grande
│  │   Windsurf_PrimaryLockup_Black.png     8096x2562
│  │   Windsurf_PrimaryLockup_White.png     2984x944
│  └─ customers/                25 logos SVG de clientes (ver seção 6)
├─ icons/                       16 ícones SVG da UI do site
├─ product/                     20 imagens de produto/UI (screenshots reais do Devin)
│   hero_new.webp               2600x1500  <- imagem principal do hero
│   bento01 / bento03           1288px     <- cards de features
│   integration01/02/03         1636x756   <- grade de integrações
│   devin-og-card.png           1200x630   <- card social pronto
└─ web-captures/                3 screenshots de página inteira
    devin-home-fullpage.png     1585x8891
    devin-pricing-fullpage.png  1585x5517
    cognition-home-fullpage.png 1585x1866

[External] Cognition Press Kit/  Press kit oficial (já estava na pasta)
├─ Cognition/PNG + SVG          logos + avatares quadrados black/white
├─ Devin/PNG + SVG              logos + avatares quadrados black/white
├─ Product Images/              devin-interface-1.png, devin-interface-2.png
├─ Stickers/                    4 PDFs de adesivo
└─ Cognition Wallpaper.pptx     <- já é um PPTX, bom ponto de partida

tokens/
├─ devin-tokens.css             variáveis CSS prontas (tema escuro)
├─ devin-colors.json            paleta em JSON
└─ cognition-tokens.css         variáveis do cognition.com + legado
```

---

## 6. Logos de clientes disponíveis (SVG, 25)

Anduril · AT&T · BNY · Cisco · Citi · Cognizant · Dell · Elevance Health · Exa · FOX ·
Goldman Sachs · Infosys · Intact · Itaú · Lowe's · Mercedes-Benz · Modal · NASA · Nu ·
Rivian · Santander · ServiceNow · U.S. Army · U.S. Navy · Wayfair

> São marcas de terceiros, extraídas da vitrine de clientes do próprio devin.ai.
> Ótimos para um slide de "quem usa". Use como logo wall, sem alterar cor ou proporção.

---

## 7. Receita rápida de slide

**Deck escuro (recomendado — é a cara do produto):**
- Fundo `#141414`, título branco 90%, corpo branco 52%
- Acento `#49B0FF`, positivo `#00EC7E`
- Logo: `Devin_PrimaryLockup_White.png`
- Fonte: Inter (Regular 400 / Light 300)

**Deck claro (institucional Cognition):**
- Fundo `#F7F6F5`, texto `#000000`
- Acento `#3969CA`, apoio `#0294DE` e `#21C19A`
- Logo: `Cognition_PrimaryLockup_Black.png`
- Fonte: Source Serif 4 (corpo) + Inter (títulos)

**Gráficos — ordem das séries:**
`#3969CA` → `#21C19A` → `#0294DE` → `#956CDE` → `#F58E3A`
