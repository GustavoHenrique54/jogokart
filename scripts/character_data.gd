class_name CharacterData
extends RefCounted
## Dados, balanceamento e descrições dos Personagens do Folclore Brasileiro.

const BOITATA := "boitata"
const ET_VARGINHA := "et_varginha"

const CHARACTERS: Dictionary = {
	BOITATA: {
		"id": BOITATA,
		"name": "Boitatá",
		"title": "A Lendária Cobra de Fogo",
		"lore_category": "Folclore Indígena Brasileiro (Mbaetata)",
		"lore": "O Boitatá é a colossal serpente de fogo sagrada que protege as matas do Brasil. Com corpo sinuoso feito de puro fogo-fátuo e olhos que brilham como dois sóis flamejantes, ela se enrola na madeira do rolimã e devora a pista com chamas ardentes!",
		"theme_color": Color(1.0, 0.35, 0.05), # Laranja/Vermelho fogo
		"accent_color": Color(1.0, 0.88, 0.15), # Amarelo fogo
		"passive": {
			"name": "Fogo-Fátuo da Floresta",
			"icon": "🔥",
			"tag": "PASSIVA",
			"summary": "Tração ígnea, bônus de empurrão e menor perda de embalo em aclives.",
			"description": "Ao pilotar com Boitatá, as rodas liberam fagulhas vivas que aquecem o asfalto. Ganha +20% de força de empurrão (W), perde 40% menos velocidade ao subir aclives ou lombadas e recebe +15% de tração nas curvas fechadas."
		},
		"ability_damage": {
			"name": "Labareda Voraz",
			"icon": "💥",
			"tag": "HABILIDADE 1 — DANO",
			"key_pc": "Q",
			"key_joy": "X / ▢",
			"cooldown": 5.0,
			"summary": "Dispara uma esfera veloz de fogo ancestral que explode ao atingir oponentes ou o solo.",
			"description": "Lança uma orbe incandescente para a frente. No impacto, causa uma explosão flamejante que atordoa o kart atingido, causando perda imediata de 30% da velocidade, forte recuo (knockback) e fumaça."
		},
		"ability_barrier": {
			"name": "Manto de Fogo Sagrado",
			"icon": "🛡️",
			"tag": "HABILIDADE 2 — BARREIRA",
			"key_pc": "E",
			"key_joy": "Y / △",
			"cooldown": 8.0,
			"duration": 4.0,
			"summary": "Cria um anel giratório de labaredas protetoras que anula danos e repele oponentes.",
			"description": "Envolve o rolimã em um anel de chamas vivas por 4 segundos. Enquanto ativo, o jogador fica imune a projéteis e perda de velocidade em batidas com muretas. Qualquer kart que encostar no escudo é repelido com fogo!"
		}
	},
	ET_VARGINHA: {
		"id": ET_VARGINHA,
		"name": "ET Clássico",
		"title": "O Extraterrestre dos Filmes",
		"lore_category": "Ficção Científica & Folclore Moderno",
		"lore": "O icônico alienígena 'Grey' dos cinemas e filmes clássicos de ficção científica. Possui crânio bulboso proeminente, pele cinzenta perolada e gigantescos olhos negros amendoados espelhados. Utiliza campos antigravitacionais para flutuar suavemente pelos morros!",
		"theme_color": Color(0.25, 0.82, 0.95), # Ciano cósmico
		"accent_color": Color(0.85, 0.88, 0.95), # Prata estelar
		"passive": {
			"name": "Gravidade dos Filmes",
			"icon": "🛸",
			"tag": "PASSIVA",
			"summary": "Queda suave, arrasto aéreo reduzido e ZERO penalidade de impacto no pouso.",
			"description": "A tecnologia alienígena reduz a gravidade em 30% quando está no ar. Os saltos em lombadas e cristas não punem a velocidade na aterrissagem (zero perda de embalo) e concedem controle direcional aéreo perfeito."
		},
		"ability_damage": {
			"name": "Raio de Plasma Psiônico",
			"icon": "⚡",
			"tag": "HABILIDADE 1 — DANO",
			"key_pc": "Q",
			"key_joy": "X / ▢",
			"cooldown": 5.0,
			"summary": "Dispara um projétil de plasma extraterrestre que desestabiliza o veículo atingido.",
			"description": "Atira um feixe eletromagnético que busca a pista à frente. Ao acertar um kart adversário, cria uma sobrecarga gravitacional temporária que joga o alvo levemente para cima e descontrola a direção do adversário."
		},
		"ability_barrier": {
			"name": "Cúpula de Força Alienígena",
			"icon": "🔮",
			"tag": "HABILIDADE 2 — BARREIRA",
			"key_pc": "E",
			"key_joy": "Y / △",
			"cooldown": 8.0,
			"duration": 4.0,
			"summary": "Projeta uma cúpula semitransparente que bloqueia ataques e zera a resistência do ar.",
			"description": "Ergue um campo de força esférico que dura 4 segundos. Anula projéteis inimigos, corta a resistência aerodinâmica a zero (permitindo deslizar livremente mesmo contra o vento) e desvia obstáculos da pista."
		}
	}
}


static func get_character(id: String) -> Dictionary:
	if CHARACTERS.has(id):
		return CHARACTERS[id]
	return CHARACTERS[BOITATA]


static func get_all_characters() -> Array:
	return [CHARACTERS[BOITATA], CHARACTERS[ET_VARGINHA]]
