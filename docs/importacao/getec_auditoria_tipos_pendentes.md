# Auditoria — 63 bens sem tipo classificado e 51 warnings (PROMPT 8.11)

Documento **somente de leitura/diagnóstico**. Nenhuma linha aqui foi aplicada ao
classificador, ao `ImportAnalyzer` ou ao `GetecImportProfile` — é o resultado de
um script auxiliar local (`tool/_tmp_prompt811_auditoria.dart`, descartado após
o uso), rodado 100% offline contra a planilha real `local_test_data/BENS DA
GETEC.xlsx`, com repositórios fake em memória que replicam o catálogo real já
confirmado no preflight (PROMPT 8.10): 14 tipos ativos, 15 localizações ativas
da GETEC. Nenhuma chamada de rede, nenhuma escrita no Supabase.

Sanity check: rodando o pipeline de produção (`PatrimonioImportController` real,
`ImportAnalyzer`, `GetecImportProfile`) contra os dados acima, o resultado bate
exatamente com o preflight real do PROMPT 8.10: **1743 total, 1680 aptas, 63
bloqueadas por tipo, 51 warnings**.

---

## 1. Os 63 bens sem tipo — tabela completa, agrupada

Todas as sugestões abaixo usam **exclusivamente** os 14 tipos ativos reais:
Notebook, Desktop, Monitor, Impressora, Nobreak, Servidor, TV, Projetor,
Equipamento de Rede, Estabilizador, Mobiliário, Software / Licença,
Certificado Digital, Outros. Nenhum tipo novo foi inventado.

Motivo de bloqueio em 100% dos 63: `Tipo é obrigatório e está vazio nesta
linha` — nenhuma das regras determinísticas de `inferirTipoPorDescricao` bateu.

### Grupo: RACK (armário/gabinete) — 12 registros — MÉDIA — decisão humana

| numero_patrimonio | tombamento_anterior | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|---|
| 2316880 | — | RACK 04 | SEM MARCA | — | GETEC - UNIVERSITÁRIO |
| 2485064 | 505117 | RACK PARA INFORMÁTICA | MARCA NÃO INFORMADA | — | GETEC - UNIVERSITÁRIO |
| 502824 | 0624315 | RACK 3 COMPARTIMENTOS | MARCA NÃO INFORMADA | — | SALA DOS INSERVÍVEIS |
| 3559564 | — | RACK PADRAO PISO 19" PRETO 40U X 670MM - SEI: 202400017008282 | GFORCE | — | PARQUE AMAZÔNIA - RACK GABINETE |
| 3559560 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | PARQUE AMAZÔNIA - RACK PISO II |
| 3559561 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | PARQUE AMAZÔNIA - RACK PISO II |
| 3559562 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | PARQUE AMAZÔNIA - RACK PISO II |
| 3559563 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | PARQUE AMAZÔNIA - RACK PISO II |
| 3559556 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | SEDE - PARQUE AMAZÔNIA - PISO I |
| 3559557 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | SEDE - PARQUE AMAZÔNIA - PISO I |
| 3559558 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | SEDE - PARQUE AMAZÔNIA - PISO I |
| 3559559 | — | RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282 | GFORCE | — | SEDE - PARQUE AMAZÔNIA - PISO I |

**tipo_atual_inferido**: Não identificado. **sugestao_de_tipo**: Equipamento de
Rede (lean, não definitivo). **justificativa**: rack é o gabinete físico que
abriga equipamento de rede/servidores, mas em vários catálogos patrimoniais é
tratado como Mobiliário; este mesmo dilema já havia sido marcado como
"decisão pendente" num diagnóstico anterior (PROMPT 8.7) — mantenho a mesma
cautela aqui, não é uma regra segura.

### Grupo: PONTO DE ACESSO RUCKUS — 4 registros — ALTA — regra segura proposta

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|
| 2318027 | PONTO DE ACESSO RUCKUS R610 - N. de Série: 422049001989 | RUCKUS | 422049001989 | DATACENTER - UNIVERSITÁRIO |
| 2317984 | PONTO DE ACESSO RUCKUS R610 - N. de Série: 412049003167 | RUCKUS | 412049003167 | GETEC - UNIVERSITÁRIO |
| 2318000 | PONTO DE ACESSO RUCKUS R610 - N. de Série: 422049001543 | RUCKUS | 422049001543 | GETEC - UNIVERSITÁRIO |
| 2318104 | PONTO DE ACESSO RUCKUS R610 - N. de Série: 412049002907 | RUCKUS | 412049002907 | GETEC - UNIVERSITÁRIO |

**sugestao_de_tipo**: Equipamento de Rede. **justificativa**: o classificador
já tem a palavra-chave em inglês `"access point"`, mas a planilha real usa o
termo em português "PONTO DE ACESSO" — nenhuma regra bate. Termo específico e
inequívoco, sem risco de capturar outro equipamento.

### Grupo: TELEVIISOR LED (typo real) — 4 registros — ALTA — regra segura proposta

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|
| 2342969 | TELEVIISOR LED SMARTV 55 POL - N. de Série: 102AZUJ5L918 | LG | 102AZUJ5L918 | GETEC - CANIDÉ |
| 2342966 | TELEVIISOR LED SMARTV 55 POL - N. de Série: 010AZPUER064 | LG | 010AZPUER064 | GETEC - CORUJA SUINDARA |
| 2342964 | TELEVIISOR LED SMARTV 55 POL - N. de Série: 010AZTH03537 | LG | 010AZTH03537 | GETEC - LOBO GUARA |
| 2342957 | TELEVIISOR LED SMARTV 55 POL - N. de Série: 009AZBZ1F869 | LG | 009AZBZ1F869 | GETEC - ONÇA PINTADA |

**sugestao_de_tipo**: TV. **justificativa**: erro de digitação real na
planilha ("TELEVIISOR" com "ii" duplo) — nem "televisao" nem "tv" (como
palavra isolada) batem. Variante de grafia exata, específica, risco nulo de
confundir outro equipamento.

### Grupo: TELA INTERATIVA LG (painel touch 65") — 4 registros — MÉDIA — decisão humana

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|
| 3627174 | TELA INTERATIVA 65 LG 4K TOUCH SCREEN 65TR3DK - N. de Série: 310GLMW02939 | LG | 310GLMW02939 | GETEC - CORUJA SUINDARA |
| 3627173 | TELA INTERATIVA 65 LG 4K TOUCH SCREEN 65TR3DK - N. de Série: 309GLLX02064 | LG | 309GLLX02064 | GETEC - LOBO GUARA |
| 3627175 | TELA INTERATIVA 65 LG 4K TOUCH SCREEN 65TR3DK - N. de Série: 309GLWJ02097 | LG | 309GLWJ02097 | GETEC - ONÇA PINTADA |
| 3627178 | TELA INTERATIVA 65 LG 4K TOUCH SCREEN 65TR3DK - N. de Série: 309GLXK02098 | LG | 309GLXK02098 | SEDE - PARQUE AMAZÔNIA - PISO I |
**sugestao_de_tipo**: TV (mais próximo entre os 14, por ser tela grande de
parede). **justificativa**: é um painel interativo/touch, arquitetural e
funcionalmente diferente de uma TV comum — o catálogo atual não tem categoria
"Painel Interativo"/"Smart Board". Precisa confirmação humana antes de
qualquer regra.

### Grupo: GARANTIA ESTENDIDA — 4 registros — MÉDIA — decisão humana (de negócio)

| numero_patrimonio | descricao | marca | localizacao_original |
|---|---|---|---|
| 2830356 | GARANTIA ESTENDIDA | SEM MARCA | INTANGÍVEIS |
| 2830357 | GARANTIA ESTENDIDA | SEM MARCA | INTANGÍVEIS |
| 2830358 | GARANTIA ESTENDIDA | SEM MARCA | INTANGÍVEIS |
| 2830359 | GARANTIA ESTENDIDA | SEM MARCA | INTANGÍVEIS |

**sugestao_de_tipo**: Outros. **justificativa**: não é um bem físico — é um
serviço/contrato. "Outros" é o único destino tecnicamente possível entre os
14, mas a pergunta real é de processo: esses registros deveriam sequer virar
um "patrimônio" com tipo? Decisão de negócio, não de classificação de texto.

### Grupo: OPTIPLEX / OPTPLEX (Dell, inclui 1 variante com erro de digitação) — 4 registros — ALTA — regra segura proposta

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|
| 4041082 | OPTIPLEX SMALL FORM FACTOR 7020 - - N. de Série: 8HDHCD4 | DELL | 8HDHCD4 | GETEC - UNIVERSITÁRIO |
| 4041083 | OPTIPLEX SMALL FORM FACTOR 7020 - - N. de Série: 1JDHCD4 | DELL | 1JDHCD4 | GETEC - UNIVERSITÁRIO |
| 4041163 | OPTIPLEX SMALL FORM FACTOR 7020 - N. de Série: 6HDHCD4 | DELL | 6HDHCD4 | GETEC - UNIVERSITÁRIO |
| 3780834 | COMPUTADOR OPTPLEX 780 (PAT. ANTERIOR: 2316757) - N. de Série: 2SNLWQ1 | DELL | 2SNLWQ1 | GETEC - UNIVERSITÁRIO |

**sugestao_de_tipo**: Desktop. **justificativa**: Dell OptiPlex é sempre um
computador desktop (torre/SFF) — nome de linha de produto específico, nunca
outra coisa. A 4ª linha tem o mesmo modelo com erro de digitação real
("OPTPLEX", sem o "I").

### Grupo: KIT INTELLITONE (Fluke, localizador de cabo) — 3 registros — MÉDIA — decisão humana

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|
| 3218332 | KIT INTELLITONE 200 PRO - GERADOR DE TOM /IDENTIFACADOR - MT-8200-60-KIT - FLUKE - N. de Série: 22400506 | FLUKE | 22400506 | BAIXAS LOCALIZADAS |
| 3218333 | (idem) - N. de Série: 22361886 | FLUKE | 22361886 | BAIXAS LOCALIZADAS |
| 3218334 | (idem) - N. de Série: 22361934 | FLUKE | 22361934 | BAIXAS LOCALIZADAS |

**sugestao_de_tipo**: Equipamento de Rede (ferramenta de identificação/teste
de cabeamento de rede). **justificativa**: é uma ferramenta de bancada, não
infraestrutura de rede permanente — "Outros" também seria defensável. Decisão
humana.

### Grupo: MULTÍMETRO FLUKE — 3 registros — ALTA — regra segura proposta

| numero_patrimonio | descricao | marca | localizacao_original |
|---|---|---|---|
| 3072383 | MULTÍMETRO FLUKE 107 | FLUKE | GETEC - UNIVERSITÁRIO |
| 3072384 | MULTÍMETRO FLUKE 107 | FLUKE | GETEC - UNIVERSITÁRIO |
| 3072385 | MULTÍMETRO FLUKE 107 | FLUKE | GETEC - UNIVERSITÁRIO |

**sugestao_de_tipo**: Outros. **justificativa**: instrumento de medição
elétrica — não é nenhum dos outros 13 tipos, "Outros" é inequívoco aqui
(risco de falso positivo em outro equipamento é nulo).

### Grupo: PARAFUSADEIRA E FURADEIRA BOSCH — 2 registros — ALTA — regra segura proposta

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|
| 3187434 | PARAFUSADEIRA E FURADEIRA BOSCH GSR 1000 SMART 12V - N. de Série: 323111570 | BOSCH | 323111570 | GETEC - UNIVERSITÁRIO |
| 3187435 | PARAFUSADEIRA E FURADEIRA BOSCH GSR 1000 SMART 12V - N. de Série: 323111568 | BOSCH | 323111568 | SEDE - PARQUE AMAZÔNIA - PISO I |

**sugestao_de_tipo**: Outros. **justificativa**: ferramenta manual, claramente
fora de todas as outras 13 categorias.

### Grupo: ESTAÇÃO DE TRABALHO DELL PRECISION — 2 registros — ALTA — regra segura proposta

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original |
|---|---|---|---|---|
| 2242960 | ESTAÇÃO DE TRABALHO DELL PRECISION T5820 - GABINETE - PERIFÉRICOS - N. de Série: F8T9423 | DELL | F8T9423 | GETEC - UNIVERSITÁRIO |
| 2242958 | ESTAÇÃO DE TRABALHO DELL PRECISION T5820 - GABINETE - PERIFÉRICOS - N. de Série: F8R3423 | DELL | F8R3423 | HOME OFFICE |

**sugestao_de_tipo**: Desktop. **justificativa**: "estação de trabalho"
(workstation) é uma classe de computador desktop de alta performance —
Dell Precision é sempre um desktop/torre.

### Grupo: BANCO DE BATERIAS — 2 registros — MÉDIA — decisão humana

| numero_patrimonio | descricao | marca | localizacao_original |
|---|---|---|---|
| 2564234 | BANCO DE BATERIAS 16 BATERIAS | SENUS | DATACENTER - UNIVERSITÁRIO |
| 2564235 | BANCO DE BATERIAS 16 BATERIAS | SENUS | DATACENTER - UNIVERSITÁRIO |

**sugestao_de_tipo**: Nobreak (lean, por associação com sistema de UPS do
datacenter). **justificativa**: é um acessório/componente de nobreak, não o
nobreak em si — pode ser mais correto classificar como "Outros". Decisão
humana.

### Registros únicos (grupos de 1) — detalhe completo

| numero_patrimonio | descricao | marca | numero_serie | localizacao_original | sugestao_de_tipo | confiança | justificativa |
|---|---|---|---|---|---|---|---|
| 2534854 | MAC MINI M18C SILV 256GB - N. de Série: MGNR3BZ/A | APPLE | MGNR3BZ/A | BAIXAS LOCALIZADAS | Desktop | ALTA | Mac Mini é um computador desktop compacto — categoria de produto inequívoca. |
| 2534855 | MAGIC APPLE KEYBOARD - N. de Série: MLA22BZ/A | APPLE | MLA22BZ/A | BAIXAS LOCALIZADAS | Outros | BAIXA | Acessório/periférico (teclado) — mesma cautela pedida explicitamente para teclado/mouse/webcam: não decidir silenciosamente. |
| 2534856 | MAGIC APPLE TRACKPAD 2 - N. de Série: MJ2R2BE/A | APPLE | MJ2R2BE/A | BAIXAS LOCALIZADAS | Outros | BAIXA | Acessório/periférico (trackpad) — mesma cautela do item acima. |
| 2610501 | MAGIC KEYBOARD APLLE 3 MK2A3BZ/A APPLE | APPLE | — | BAIXAS LOCALIZADAS | Outros | BAIXA | Acessório/periférico (teclado), com erro de digitação ("APLLE"). |
| 3120469 | WEBCAM LOGITECH C920 S PRO, FULL HD... | LOGITECH | 2225LZ95AJ68 | BAIXAS LOCALIZADAS | Outros | BAIXA | Acessório/periférico (webcam) — mesma cautela. |
| 3634170 | ESCADA ALUMÍNIO 8 DEGRAUS | MARCA NÃO INFORMADA | — | BAIXAS LOCALIZADAS | Outros | BAIXA | Não é equipamento de TI nem mobiliário de escritório; único destino possível é Outros, mas questionável se deveria ser um "patrimônio" tipado. |
| 616022 | DISPOSITIVO DE ARMAZENAMENTO DE DADOS EMC² VNXE1600 - N. de Série: FC500163700002 | DELL | FC500163700002 | DATACENTER - UNIVERSITÁRIO | Servidor | MÉDIA | Storage array de datacenter — mais próximo de Servidor que de Equipamento de Rede, mas não é literalmente um "servidor". |
| 2316912 | ARCONDICIONADO ELETROLUX | ELETROLUX | — | DATACENTER - UNIVERSITÁRIO | Outros | ALTA | Ar-condicionado, grafia sem espaço ("ARCONDICIONADO") — o classificador já trata "ar condicionado" (com espaço) como Outros; só falta a variante sem espaço. |
| 503483 | FRIGOBAR ELECTROLUZ RE 120 | MARCA NÃO INFORMADA | — | GETEC - UNIVERSITÁRIO | Outros | ALTA | Eletrodoméstico, claramente fora de todas as outras 13 categorias. |
| 2316831 | 18 BTUS | SEM MARCA | — | GETEC - UNIVERSITÁRIO | Outros (palpite) | BAIXA | Descrição incompleta/truncada (provavelmente um ar-condicionado, mas o texto não confirma) — problema de qualidade de dado, precisa revisão manual na origem. |
| 2465390 | TELEFONE SEM FIO KX-TG3881LB - N. de Série: 9FBQC173205 | PANASONIC | 9FBQC173205 | GETEC - UNIVERSITÁRIO | Outros | MÉDIA | Telefone fixo sem fio — catálogo não tem tipo "Telefonia"; Outros é o único destino, mas vale confirmar se há intenção de criar essa categoria no futuro (fora do escopo desta auditoria: não invento tipo novo). |
| 2485378 | COMPUTADOR COMPAQ PRO 4300 - N. de Série: BRG306FDGP | HP | BRG306FDGP | GETEC - UNIVERSITÁRIO | Desktop | ALTA | HP Compaq Pro é uma linha de desktop corporativo — nome de produto específico. |
| 2759296 | COMPUTADOR THINKCENTER M81 - N. de Série: L1C4TAD | LENOVO | L1C4TAD | GETEC - UNIVERSITÁRIO | Desktop | ALTA | Lenovo ThinkCentre é sempre um desktop — nome de linha de produto específico. |
| 3908303 | CPUI5 13500 16GB 512 SSD - N. de Série: 09233011402101000340 | C3TECH | 09233011402101000340 | GETEC - UNIVERSITÁRIO | Desktop | ALTA (sugestão) / MÉDIA (regra) | Claramente um desktop (CPU i5, 16GB RAM, SSD 512) para um humano, mas "CPU" está colado ao código do processador ("CPUI5") sem espaço — a checagem de fronteira de palavra do classificador (que evita falsos positivos) bloqueia o match; soltar essa fronteira tem risco maior de efeito colateral em outras descrições, por isso a REGRA fica na categoria "decisão humana" mesmo com a sugestão em si sendo confiável. |
| 4057378 | IPHONE SE 2TH BLACK 64GB MHGP3BR/A APPLE - N. de Série: DV6GM2ALPJQ | APPLE | DV6GM2ALPJQ | GETEC - UNIVERSITÁRIO | Outros | ALTA | Smartphone — catálogo não tem tipo "Celular/Smartphone" (não inventado aqui); Outros é o único destino possível e inequívoco. |
| 2672755 | OFFICE HOME AND BUSSINES 2019 ESD | MICROSOFT | — | INTANGÍVEIS | Software / Licença | ALTA | Licença de software Microsoft Office, com erro de digitação real ("BUSSINES" em vez de "BUSINESS") — o classificador já tem a frase correta como palavra-chave, só falta esta variante de grafia. |
| 503650 | TELA TES TRM200S EB | MARCA NÃO INFORMADA | — | SEDE - PARQUE AMAZÔNIA - PISO I | Monitor (palpite) | BAIXA | Descrição muito genérica/pouco clara ("TELA" sugere tela/monitor, mas o modelo "TES TRM200S" não é identificável) — precisa revisão manual. |
| 504621 | ETIQUETADORA BROTHER PT-65 - N. de Série: U52663-J1J858147 | BROTHER | U52663-J1J858147 | SEDE - PARQUE AMAZÔNIA - PISO I | Impressora | MÉDIA | Impressora de etiquetas — é uma impressora especializada, mas algumas organizações preferem tratá-la como "Outros"; vale confirmação. |
| 3600466 | GAVETEORP 91703 MONTADO SAV/SAV | AVANTTI | — | SEDE - PARQUE AMAZÔNIA - PISO I | Mobiliário (palpite) | BAIXA | Provável erro de digitação de "GAVETEIRO" (que já é palavra-chave de Mobiliário) — mas não posso confirmar a intenção sem revisão humana; não crio uma regra baseada num palpite de typo não confirmado. |

---

## 2. Agrupamento — 30 grupos entre os 63

| Grupo | Qtd | Sugestão | Confiança |
|---|---|---|---|
| RACK (armário/gabinete) | 12 | Equipamento de Rede (lean) | MÉDIA |
| PONTO DE ACESSO RUCKUS | 4 | Equipamento de Rede | ALTA |
| TELEVIISOR LED (typo) | 4 | TV | ALTA |
| TELA INTERATIVA LG | 4 | TV (lean) | MÉDIA |
| GARANTIA ESTENDIDA | 4 | Outros | MÉDIA |
| OPTIPLEX / OPTPLEX (Dell) | 4 | Desktop | ALTA |
| KIT INTELLITONE (Fluke) | 3 | Equipamento de Rede (lean) | MÉDIA |
| MULTÍMETRO FLUKE | 3 | Outros | ALTA |
| PARAFUSADEIRA E FURADEIRA BOSCH | 2 | Outros | ALTA |
| ESTAÇÃO DE TRABALHO DELL PRECISION | 2 | Desktop | ALTA |
| BANCO DE BATERIAS | 2 | Nobreak (lean) | MÉDIA |
| MAC MINI | 1 | Desktop | ALTA |
| MAGIC APPLE KEYBOARD | 1 | Outros | BAIXA |
| MAGIC APPLE TRACKPAD 2 | 1 | Outros | BAIXA |
| MAGIC KEYBOARD APPLE 3 | 1 | Outros | BAIXA |
| WEBCAM LOGITECH | 1 | Outros | BAIXA |
| ESCADA | 1 | Outros | BAIXA |
| DISPOSITIVO ARMAZENAMENTO EMC VNXE1600 | 1 | Servidor | MÉDIA |
| ARCONDICIONADO ELETROLUX (sem espaço) | 1 | Outros | ALTA |
| FRIGOBAR ELECTROLUZ | 1 | Outros | ALTA |
| 18 BTUS (descrição incompleta) | 1 | Outros (palpite) | BAIXA |
| TELEFONE SEM FIO PANASONIC | 1 | Outros | MÉDIA |
| COMPUTADOR COMPAQ PRO 4300 | 1 | Desktop | ALTA |
| COMPUTADOR THINKCENTER M81 | 1 | Desktop | ALTA |
| CPUI5 13500 (sem espaço) | 1 | Desktop | ALTA (sugestão) / MÉDIA (regra) |
| IPHONE SE | 1 | Outros | ALTA |
| OFFICE HOME AND BUSSINES (typo) | 1 | Software / Licença | ALTA |
| TELA TES TRM200S EB | 1 | Monitor (palpite) | BAIXA |
| ETIQUETADORA BROTHER PT-65 | 1 | Impressora | MÉDIA |
| GAVETEORP 91703 (provável "gaveteiro") | 1 | Mobiliário (palpite) | BAIXA |

**Totais de confiança**: ALTA = 27, MÉDIA = 28, BAIXA = 8 (soma = 63).

---

## 3. Auditoria dos 51 warnings

### 3.1 `possivelBaixa` — 45 ocorrências

- **Mensagem**: "Esta localização sugere que o patrimônio pode estar baixado.
  A carga inicial não aplicará status Baixado automaticamente."
- **Motivo**: `GetecImportProfile.indicaBaixa()` marca qualquer linha cuja
  localização (texto original da planilha) contenha "baixa" — as 45 linhas
  com localização = `BAIXAS LOCALIZADAS`.
- **Impacto na importação**: nenhum bloqueio. É só um alerta visual para o
  usuário revisar; o status do patrimônio cadastrado continua sempre
  `DISPONIVEL`/conforme regra padrão de cadastro — nunca `BAIXADO`
  automaticamente (comportamento já coberto por teste desde o Prompt 8.9).
- **Patrimônios envolvidos** (45): 504373, 504797, 504812, 504819, 771944,
  2248190, 2248207, 2248211, 2277573, 2485369, 2534854, 2534855, 2534856,
  2564336, 2589630, 2610501, 2723613, 2733243, 2771523, 2913071, 2913097,
  2917778, 2991339, 3120469, 3168145, 3168289, 3170575, 3170765, 3187558,
  3187559, 3218332, 3218333, 3218334, 3440104, 3440125, 3441770, 3558407,
  3634170, 3724446, 3724448, 3724449, 3724450, 3731889, 3733920, 3735557.

### 3.2 `possivelDuplicidadeSerial` — 6 ocorrências

- **Mensagem**: "Número de série 'X' já aparece em outro patrimônio."
- **Motivo**: dois pares de tombamentos compartilham o mesmo número de série
  dentro da própria planilha — não é duplicidade no banco (planilha nunca foi
  importada), é duplicidade **dentro do arquivo**. Isso costuma acontecer
  quando um notebook e sua licença de Office são cadastrados como dois
  tombamentos separados, mas o número de série usado na planilha foi o do
  notebook em ambas as linhas (erro de preenchimento na fonte).
- **Impacto na importação**: nenhum bloqueio — número de série nunca é
  `unique` no banco (não é chave de identidade), é só um aviso de revisão.
- **Detalhe dos 3 grupos afetados (6 patrimônios)**:

| numero_patrimonio | numero_serie | descricao |
|---|---|---|
| 2706608 | PE08P4BS | NOTEBOOK E14 G2 I5-1135G7 8GB 256 SSD W10P 20TB0003BO |
| 2706612 | PE08P4BS | LICENÇAS MICROSOFT OFFICE HOME AND BUSINESS 2019 ESD |
| 2709450 | PE08P1GH | NOTEBOOK LENOVO E14 G2 I5-1135G7 8GB 256SSD W10P 20TB0003BO |
| 2709454 | PE08P1GH | LICENCAS MICROSOFT OFFICE HOME AND BUSINESS 2019 |
| 2714003 | PE08P3Q7 | NOTEBOOK THINKPA D E14 INTEL CORE I5 1135G7 8GB SSD256GB M.2 NVME 14 FUL HD W10PRO - 20TB0003BO |
| 2714043 | PE08P3Q7 | LICENÇAS MICROSOFT OFFICE HOME AND BUSINESS 2019 ESD |

Confirma o padrão: em cada um dos 3 pares, um Notebook e sua respectiva
licença de Office compartilham o número de série do notebook.

### 3.3 Tipos de warning NÃO encontrados nesta planilha

`Data de aquisição não reconhecida`, `Data de entrada não reconhecida`,
`Setor não encontrado` e `Setor de origem não encontrado` — zero ocorrências.
Esperado: a planilha GETEC não tem colunas de data nem de setor/origem
mapeadas para o perfil GETEC (só tombamento, tomb_anterior, descrição,
localização, marca e n. série), então essas regras nunca são avaliadas com
texto presente.

**Total: 45 + 6 = 51 — bate exatamente com o preflight real.**

---

## 4. Sobreposição

| Categoria | Quantidade |
|---|---|
| Bloqueadas E com warning | 9 |
| Somente warning (não bloqueadas) | 42 |
| Completamente limpas (sem erro nem aviso) | 1638 |
| Com mais de 1 warning na mesma linha | 0 |
| **Soma de conferência** | **9 + 42 + 1638 = 1689 linhas com ao menos uma condição, + 54 bloqueadas sem warning... ver nota** |

Conferência exata por partição (cada linha cai em exatamente uma categoria):
- Bloqueadas (63) = 9 com warning + 54 sem warning.
- Não bloqueadas (1680) = 42 com warning + 1638 sem warning.
- **63 + 1680 = 1743** ✓.
- **9 + 42 + 1638 + 54 = 1743** ✓ (partição completa, sem sobreposição dupla).

As 9 linhas bloqueadas que também têm warning são exatamente as 9 do grupo
"BAIXAS LOCALIZADAS" que caíram nos 63 sem tipo (MAC MINI, MAGIC APPLE
KEYBOARD, MAGIC APPLE TRACKPAD 2, MAGIC KEYBOARD APPLE 3, WEBCAM LOGITECH,
KIT INTELLITONE ×3, ESCADA): 2534854, 2534855, 2534856, 2610501, 3120469,
3218332, 3218333, 3218334, 3634170.

Nenhuma linha tem mais de 1 warning simultâneo (confirma que `possivelBaixa`
e `possivelDuplicidadeSerial` nunca coincidem na planilha real).

---

## 5. Propostas de regras futuras (NÃO implementadas nesta etapa)

### REGRA SEGURA (risco muito baixo de classificar outro equipamento incorretamente)

Cada uma é um nome de produto específico ou uma variante de grafia/typo real
encontrada na planilha — não uma palavra genérica:

1. `"optiplex"` / `"optplex"` (typo real) → Desktop — cobre 4.
2. `"thinkcentre"` / `"thinkcenter"` (grafia real na planilha) → Desktop — cobre 1.
3. `"compaq pro"` → Desktop — cobre 1.
4. `"estacao de trabalho"` / `"workstation"` → Desktop — cobre 2.
5. `"mac mini"` → Desktop — cobre 1.
6. `"ponto de acesso"` (equivalente em português de "access point") → Equipamento de Rede — cobre 4.
7. `"televiisor"` (typo real, "ii" duplo) → TV — cobre 4.
8. `"arcondicionado"` (variante sem espaço de "ar condicionado", já existente) → Outros — cobre 1.
9. `"frigobar"` → Outros — cobre 1.
10. `"multimetro"` (sem acento — a normalização já remove acento, só falta a palavra-chave) → Outros — cobre 3.
11. `"parafusadeira"` e/ou `"furadeira"` → Outros — cobre 2.
12. `"office home and bussines"` (typo real, "bussines" em vez de "business") → Software / Licença — cobre 1.
13. `"iphone"` → Outros — cobre 1 (observação: catálogo não tem tipo "Celular"; permanece dentro dos 14 existentes).

**Total coberto por regras seguras: 26 dos 63 (≈41%)**, sem tocar em nenhuma
palavra genérica que possa colidir com outro equipamento.

### REGRA QUE EXIGE DECISÃO HUMANA

1. **RACK** (12) — Equipamento de Rede vs Mobiliário vs Outros: ambiguidade de
   categorização de negócio, não de texto.
2. **TELA INTERATIVA** (4) — TV vs Monitor vs categoria inexistente (painel
   interativo).
3. **GARANTIA ESTENDIDA** (4) — decisão de processo: deveria nem virar
   patrimônio.
4. **KIT INTELLITONE** (3) — ferramenta de rede vs "Outros".
5. **BANCO DE BATERIAS** (2) — acessório de Nobreak vs item próprio.
6. **DISPOSITIVO DE ARMAZENAMENTO EMC VNXE1600** (1) — Servidor vs
   Equipamento de Rede.
7. **ETIQUETADORA BROTHER** (1) — Impressora vs Outros.
8. **TELEFONE SEM FIO** (1) — catálogo não tem "Telefonia".
9. **Acessórios Apple** — MAGIC APPLE KEYBOARD, MAGIC APPLE TRACKPAD 2, MAGIC
   KEYBOARD APPLE 3, WEBCAM LOGITECH (4) — mesma cautela explícita pedida
   para teclado/mouse/webcam: nunca decidir silenciosamente.
10. **Dados ruins/ambíguos** — ESCADA (1), 18 BTUS/descrição truncada (1),
    TELA TES TRM200S EB (1), GAVETEORP/provável typo de "gaveteiro" (1) —
    precisam revisão humana linha a linha, não regra genérica.
11. **CPUI5 13500** (1) — sugestão confiável (Desktop) para um humano, mas a
    regra técnica (soltar a checagem de fronteira de palavra ao redor de
    "cpu") tem raio de efeito maior sobre outras descrições — fica para
    decisão humana mesmo com alta confiança na sugestão em si.

**Total nesta categoria: 37 dos 63.**

`26 (regra segura) + 37 (decisão humana) = 63` ✓.

---

## 6. Nenhum comportamento foi alterado

`ImportAnalyzer`, `GetecImportProfile`, a lógica de resolução de tipo/status
das linhas, o fluxo de cadastro e o fluxo de envio permanecem **exatamente**
como estavam antes desta auditoria. Nenhuma das regras propostas acima foi
implementada.
