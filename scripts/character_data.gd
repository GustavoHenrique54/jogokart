class_name CharacterData
extends RefCounted
## Dados, balanceamento e descrições dos Personagens do Folclore Brasileiro.

const BOITATA := "boitata"
const ET_VARGINHA := "et_varginha"
const CURUPIRA := "curupira"
const CHUPACABRA := "chupacabra"

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
			"name": "Rastro Flamejante",
			"icon": "🔥",
			"tag": "HABILIDADE 1 — CONTROLE / DANO",
			"key_pc": "Q",
			"key_joy": "X / ▢",
			"cooldown": 13.0,
			"duration": 2.5,
			"summary": "A cauda incandescente do Boitatá marca o chão com uma linha de labaredas por 2,5 segundos.",
			"description": "Ao apertar o botão, o Boitatá deixa uma linha de fogo no asfalto por 2,5 segundos. Qualquer carrinho que cruzar essa trilha sofre um tranco de atrito (rodas superaquecem), perdendo 35% da velocidade atual e patinando levemente. O fogo se apaga após 3 a 4 segundos e permite desvio a quem vier atento atrás."
		},
		"ability_barrier": {
			"name": "O Bote da Serpente",
			"icon": "🐍",
			"tag": "HABILIDADE 2 — VELOCIDADE",
			"key_pc": "E",
			"key_joy": "Y / △",
			"cooldown": 12.0,
			"duration": 1.5,
			"summary": "Projeta o carrinho violentamente morro abaixo com alta aceleração por 1,5 segundo.",
			"description": "A forma alongada e sinuosa do Boitatá se comprime e impulsiona o rolimã em linha reta com aceleração violenta por 1,5s. Vantagem tática: se colidir com outro piloto durante o bote, o Boitatá não perde velocidade e arremessa o rival de lado! Risco: a sensibilidade da direção cai drasticamente durante o ataque."
		},
		"ability_ultimate": {
			"name": "Clarão da Mata (Olhos de Brasas)",
			"icon": "☀️",
			"tag": "ULTIMATE [R] — PODER ANCESTRAL",
			"key_pc": "R",
			"key_joy": "B / ◯ ou R3",
			"cooldown": 25.0,
			"duration": 1.5,
			"summary": "Cobre a tela dos oponentes com um clarão alaranjado e causa 'Perda de Linha'.",
			"description": "Quem estiver olhando na direção do Boitatá a até distância média tem a tela ofuscada por um clarão alaranjado por 1,5 segundo. Os rivais atingidos sofrem 'Perda de Linha': a direção treme e fica mais pesada temporariamente, dificultando manter o traçado da ladeira."
		}
	},
	ET_VARGINHA: {
		"id": ET_VARGINHA,
		"name": "ET de Varginha",
		"title": "O Visitante Espacial",
		"lore_category": "Ficção Científica & Folclore Moderno",
		"lore": "O lendário visitante de Varginha e o ícone dos filmes clássicos de ficção científica. Possui crânio bulboso com três calombos na cabeça, pele cinzenta perolada e grandes olhos negros amendoados oblíquos. Equipado com engenhocas alienígenas soldadas no chassi e contato direto com a nave-mãe na floresta!",
		"theme_color": Color(0.25, 0.85, 0.95), # Ciano cósmico
		"accent_color": Color(0.72, 0.45, 1.0), # Violeta psíquico
		"passive": {
			"name": "Gravidade Ufológica",
			"icon": "🛸",
			"tag": "PASSIVA",
			"summary": "Queda suave, arrasto aéreo reduzido e ZERO penalidade de impacto no pouso.",
			"description": "A tecnologia extraterrestre reduz a gravidade em 30% no ar. Os saltos em lombadas e cristas não punem a velocidade na aterrissagem (zero perda de embalo) e concedem controle direcional aéreo perfeito."
		},
		"ability_damage": {
			"name": "Feixe Telecinético",
			"icon": "⚡",
			"tag": "HABILIDADE 1 [Q] — DANO",
			"key_pc": "Q",
			"key_joy": "X / ▢",
			"cooldown": 12.0,
			"duration": 0.0,
			"summary": "Dispara uma onda psíquica que trava as rodas do rival, faz o kart quicar e o joga de lado.",
			"description": "A criatura projeta uma onda psíquica concentrada a partir dos três calombos na cabeça em linha reta (skillshot). Ao atingir o carrinho da frente, causa curto-circuito de impacto que trava bruscamente as rodas de ferro do rival: o kart quica, perde 40% da velocidade de descida e é empurrado de lado. Se errar, bate na vegetação sem efeito na pista."
		},
		"ability_barrier": {
			"name": "Propulsor Antigravitacional",
			"icon": "🚀",
			"tag": "HABILIDADE 2 [E] — MOBILIDADE / FÍSICA",
			"key_pc": "E",
			"key_joy": "Y / △",
			"cooldown": 14.0,
			"duration": 3.0,
			"summary": "Levita o kart sobre o asfalto: atrito zero, curvas por deslize inercial e aceleração contínua.",
			"description": "Ativa um dispositivo alienígena soldado no chassi que levita o veículo por 3 segundos. Atrito zero: o rolimã para de encostar no chão, atingindo aceleração contínua sem penalidade de superaquecimento ou solo irregular. Faz curvas por 'deslize inercial' (hovercraft) em alta velocidade. Risco: bater de frente arremessa o kart para o alto!"
		},
		"ability_ultimate": {
			"name": "Abdução Espacial",
			"icon": "👽",
			"tag": "ULTIMATE [R] — LUZ DE NAVE",
			"key_pc": "R",
			"key_joy": "B / ◯ ou R3",
			"cooldown": 26.0,
			"duration": 3.5,
			"summary": "Cone de luz da nave-mãe suspende os rivais a 1m do solo e abre túnel de vácuo veloz ao ET.",
			"description": "Sinaliza para a nave-mãe que sobrevoa a floresta, abrindo um holofote cilíndrico de luz azulada que varre a pista à frente por 3,5s (com 0,5s de atraso para atingir o solo). Oponentes no cone são suspensos cerca de 1m do solo por 1,8s sem direção nem embalo. O ET ganha bônus violento de aceleração contínua para cortar os rivais por baixo sem colisão."
		}
	},
	CURUPIRA: {
		"id": CURUPIRA,
		"name": "Curupira",
		"title": "O Guardião da Floresta",
		"lore_category": "Folclore Indígena Brasileiro",
		"lore": "Guardião ágil da floresta com pés invertidos e maestria em curvas fechadas. Possui cabelos de fogo vibrantes e pés virados para trás que despistam qualquer perseguidor nas curvas da mata!",
		"theme_color": Color(0.18, 0.78, 0.35), # Verde mata
		"accent_color": Color(0.95, 0.45, 0.12), # Cabelos de fogo / Laranja vivo
		"icon": "🦶",
		"description": "Guardião ágil da floresta com pés invertidos e maestria em curvas fechadas.",
		"passive": {
			"id": "curupira_passive",
			"name": "Pegadas Invertidas",
			"icon": "🦶",
			"tag": "PASSIVA",
			"summary": "Pés virados para trás garantem tração extrema e resposta rápida em curvas.",
			"description": "Guardião ágil da floresta com pés invertidos e maestria em curvas fechadas.",
			"onUpdate": Callable()
		},
		"ability_damage": {
			"id": "curupira_q",
			"name": "Tora de Arapuca",
			"icon": "🪵",
			"tag": "HABILIDADE 1 [Q] — DANO / ARMADILHA",
			"key_pc": "Q",
			"key_joy": "X / ▢",
			"cooldown": 13.0,
			"duration": 5.0,
			"summary": "Derruba uma tora maciça de arapuca na pista que dura 5s ou até o primeiro choque.",
			"description": "O Curupira solta um tronco de arapuca imediatamente atrás do kart. O piloto que colidir sofre um impacto violento: perde 45% da velocidade atual, é arremessado para o lado da pista e tem o alinhamento das rodas desestabilizado por 1,5 segundo. A tora se despedaça após o primeiro impacto."
		},
		"ability_barrier": {
			"id": "curupira_e",
			"name": "Ginga da Mata",
			"icon": "🍃",
			"tag": "HABILIDADE 2 [E] — MOBILIDADE / CURVAS",
			"key_pc": "E",
			"key_joy": "Y / △",
			"cooldown": 10.0,
			"duration": 2.5,
			"summary": "Aumenta drasticamente a resposta de curva por 2,5s e empurra rivais de lado sem perder embalo.",
			"description": "O Curupira usa o corpo ágil e os pés virados para executar manobras angulares sem capotar o rolimã. Por 2,5s, a sensibilidade de curva sobe drasticamente com impulso lateral limpo, contornando cotovelos fechados sem frear. Choques laterais empurram o rival para fora sem cortar o próprio embalo. Risco: em retas pode raspar nos barrancos!"
		},
		"ability_ultimate": {
			"id": "curupira_r",
			"name": "Assobio Ilusório",
			"icon": "🎵",
			"tag": "ULTIMATE [R] — CONTROLE / PÂNICO",
			"key_pc": "R",
			"key_joy": "B / ◯ ou R3",
			"cooldown": 45.0,
			"duration": 2.5,
			"summary": "Inverte os comandos dos rivais próximos por 2,5s e concede +30% de aceleração contínua ao Curupira.",
			"description": "Solta um assobio agudo ecoante (aviso de 0,3s) que atinge os oponentes em área: inverte os controles direcionais (esquerda/direita) por 2,5s e projeta névoa com sombras ilusórias nas laterais da tela. O Curupira ganha 30% a mais de aceleração contínua na descida por 3 segundos."
		}
	},
	CHUPACABRA: {
		"id": CHUPACABRA,
		"name": "Chupa-Cabra",
		"title": "O Predador Noturno",
		"lore_category": "Lenda Urbana & Mistério dos Anos 90",
		"lore": "Predador implacável dos anos 90, especialista em roubo de embalo e perseguição no vácuo. Com garras afiadas, crista de espinhos dorsais e olhos rubros incandescentes que espreitam nas curvas sombrias da serra!",
		"theme_color": Color(0.88, 0.15, 0.15), # Vermelho carmesim / predador
		"accent_color": Color(0.55, 0.10, 0.65), # Roxo sombrio
		"icon": "🩸",
		"description": "Predador implacável dos anos 90, especialista em roubo de embalo e perseguição no vácuo.",
		"passive": {
			"id": "chupa_passive",
			"name": "Sede de Embalo",
			"icon": "🩸",
			"tag": "PASSIVA",
			"summary": "O cone de vácuo (slipstream) atrás de outros karts é 50% maior em largura e alcance (+35% de ganho de embalo).",
			"description": "O cone de vácuo atrás de outros karts é 50% maior em largura e alcance. Quando posicionado atrás de qualquer kart oponente, ganha +35% de aceleração contínua morro abaixo, alcançando a velocidade terminal muito mais rápido.",
			"onUpdate": Callable()
		},
		"ability_damage": {
			"id": "chupa_q",
			"name": "Mordida no Eixo",
			"icon": "🦷",
			"tag": "HABILIDADE 1 [Q] — DANO",
			"key_pc": "Q",
			"key_joy": "X / ▢",
			"cooldown": 12.0,
			"duration": 0.0,
			"summary": "Ataque frontal corpo a corpo (3 a 4m): reduz 40% da velocidade e causa superaquecimento por 2,5s.",
			"description": "Ataque frontal corpo a corpo que atinge o oponente imediatamente à frente em raio de 3 a 4 metros. Ao acertar, aplica penalidade imediata de -40% de velocidade e causa superaquecimento temporário das rodas por 2,5s (o rival patina e perde aceleração). Se errar, o Chupa-Cabra perde 8% da sua velocidade atual como recuo no ar.",
			"trigger": Callable()
		},
		"ability_barrier": {
			"id": "chupa_e",
			"name": "Bote Noturno",
			"icon": "🦇",
			"tag": "HABILIDADE 2 [E] — MOBILIDADE",
			"key_pc": "E",
			"key_joy": "Y / △",
			"cooldown": 10.0,
			"duration": 1.2,
			"summary": "Salto rasante para a frente por 1,2s; imune a atrito e obstáculos com boost de aterrissagem.",
			"description": "Salto rasante para a frente acompanhando o ângulo da ladeira com impulso instantâneo por 1,2s. Durante esse intervalo, o carrinho fica imune a atrito com o solo e passa por cima de obstáculos rasteiros (lama, poças, troncos baixos). Ao aterrissar alinhado à pista, ganha boost temporário de tração e embalo.",
			"trigger": Callable()
		},
		"ability_ultimate": {
			"id": "chupa_r",
			"name": "Drenagem Espinhal",
			"icon": "☠️",
			"tag": "ULTIMATE [R] — DRENAGEM / TETHER",
			"key_pc": "R",
			"key_joy": "B / ◯ ou R3",
			"cooldown": 45.0,
			"duration": 4.0,
			"summary": "Vincula tentáculos sombrios ao líder/oponente à frente até 25m, drenando velocidade contínua por 4s.",
			"description": "Vincula tentáculos sombrios ao kart líder ou mais próximo à frente em até 25 metros, drenando 8% de velocidade de descida por segundo durante 4,0s e convertendo em aceleração para si. O vínculo rompe se o alvo abrir mais de 35m ou virar atrás de obstáculos.",
			"trigger": Callable()
		},
		"abilityQ": {
			"id": "chupa_q",
			"name": "Mordida no Eixo",
			"key": "Q",
			"cooldown": 12.0,
			"trigger": Callable()
		},
		"abilityE": {
			"id": "chupa_e",
			"name": "Bote Noturno",
			"key": "E",
			"cooldown": 10.0,
			"trigger": Callable()
		},
		"abilityR": {
			"id": "chupa_r",
			"name": "Drenagem Espinhal",
			"key": "R",
			"cooldown": 45.0,
			"trigger": Callable()
		}
	}
}


static func get_character(id: String) -> Dictionary:
	if CHARACTERS.has(id):
		return CHARACTERS[id]
	return CHARACTERS[BOITATA]


static func get_all_characters() -> Array:
	return [CHARACTERS[BOITATA], CHARACTERS[ET_VARGINHA], CHARACTERS[CURUPIRA], CHARACTERS[CHUPACABRA]]
