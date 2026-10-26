/// Portuguese (Brazil) translations for the complete Reports interface.
///
/// The catalog and report data are translated by the API. These entries cover
/// every static label rendered by the shell, public pages, authentication flow,
/// report editor and artifact generator.
const Map<String, String> portugueseAdditional = {
  'share_link':'Link',
  'share_embed':'Incorporar',
  'share_embed_copy':'Copiar código de incorporação',
  'share_embed_help':'Incorpore este gráfico ou tabela individual. O mesmo descritor está disponível pela API.',
  'share_embed_copied':'Código de incorporação copiado',

  // Architecture page.
  'arch_title': 'Reports',
  'arch_subtitle': 'Registros, cálculos e painéis',
  'arch_k_overview': 'Visão geral',
  'arch_k_de': 'Engenharia de dados',
  'arch_k_backend': 'Backend',
  'arch_k_security': 'Segurança',
  'arch_k_frontend': 'Frontend',
  'arch_k_platform': 'Plataforma',
  'arch_s1_p1': 'O Reports recebe registros dos projetos Asodya. Ele verifica cada registro e calcula os conjuntos de dados de cada gráfico.',
  'arch_s1_p2': 'A interface mostra os conjuntos de dados como painéis, tabelas e mapas. O navegador gera os arquivos PDF, Markdown e CSV.',
  'arch_s1_p3': 'O Reports não coleta dados. Cada projeto envia seus próprios registros. Os detalhes dos projetos vêm do domain_api, e as imagens de capa são mídias do FSM servidas pelo domain_api.',
  'arch_t_projects': 'Projetos',
  'arch_t_reports': 'Relatórios',
  'arch_t_charts': 'Gráficos',
  'arch_t_rows': 'Linhas de dados',
  'arch_s2_t': 'Fluxo de dados',
  'arch_s2_s': 'De um registro até um gráfico',
  'arch_s2_p1': 'Um projeto envia um lote de registros para a API de ingestão do seu esquema.',
  'arch_s2_p2': 'A barreira verifica cada registro contra a versão publicada do esquema. Se um registro estiver errado, o motor não grava nada.',
  'arch_s2_p3': 'Uma versão de cálculo transforma os registros em um conjunto de dados. A interface lê o conjunto pelo gateway api_for_apps.',
  'arch_f1_t': 'Produtor',
  'arch_f1_d': 'Lote de registros',
  'arch_f2_t': 'Barreira',
  'arch_f2_d': 'Verificação do esquema',
  'arch_f3_d': 'Registros gravados',
  'arch_f4_t': 'Cálculo',
  'arch_f4_d': 'Versão publicada',
  'arch_f5_d': 'Resposta em cache',
  'arch_f6_t': 'Interface',
  'arch_f6_d': 'Gráficos e arquivos',
  'arch_s3_t': 'Esquemas versionados',
  'arch_s3_s': 'Uma nova versão não precisa de migração',
  'arch_s3_p1': 'Um projeto registra um rascunho de esquema com nome, versão e campos, por exemplo telemetry_event versão 1 do Cortex.',
  'arch_s3_p2': 'Uma versão publicada nunca muda. Uma mudança cria uma nova versão, e os registros antigos continuam válidos.',
  'arch_s3_p3': 'Um cálculo informa as versões de esquema que lê. Uma versão mais nova do esquema marca para revisão os rascunhos que leem a antiga.',
  'arch_s4_t': 'Armazenamento',
  'arch_s4_s': 'Três armazenamentos, cada um com uma tarefa',
  'arch_s4_p1': 'O PostgreSQL guarda o catálogo, as versões de esquema e de cálculo, as permissões e os papéis.',
  'arch_s4_p2': 'O CouchDB guarda os registros e os snapshots dos conjuntos de dados. O id de um registro vem do projeto, do esquema e da chave, então um lote repetido não grava nada novo.',
  'arch_s4_p3': 'O Redis guarda respostas calculadas por tempo limitado. Ele é um cache, não um armazenamento.',
  'arch_tile_pg': 'Catálogo, versões, permissões e papéis',
  'arch_tile_couch': 'Registros e snapshots de conjuntos de dados',
  'arch_tile_redis': 'Cache com tags de dependência e uma trava',
  'arch_s5_t': 'Cache',
  'arch_s5_s': 'Dados atuais sem trabalho repetido',
  'arch_s5_p1': 'Uma resposta calculada fica no Redis por uma hora, por padrão.',
  'arch_s5_p2': 'Cada resposta tem tags de dependência. Novos registros de um esquema removem só as respostas que leem esse esquema.',
  'arch_s5_p3': 'Uma requisição calcula a resposta que falta e as outras esperam por ela. A inicialização do motor não faz trabalho: abre os armazenamentos, verifica o esquema do banco e escuta.',
  'arch_c1': 'Resposta no Redis: nenhum cálculo',
  'arch_c2': 'Sem resposta: um cálculo atrás de uma trava',
  'arch_c3': 'Novos registros: as respostas com a tag saem do cache',
  'arch_c4': 'Redis indisponível: o motor responde sem cache',
  'arch_s6_t': 'Login',
  'arch_s6_s': 'O mesmo login Asodya do Cortex e do Certifications',
  'arch_s6_p1': 'Entrar abre o auth_apps com o contexto criptografado do Reports.',
  'arch_s6_p2': 'O auth_apps devolve o navegador para /sync com um token de uso único. O gateway resgata o token uma vez e grava os cookies da sessão.',
  'arch_s6_p3': 'Uma sessão com falha ou expirada nunca redireciona sozinha. A página continua aberta para um visitante, então não pode haver ciclo de login.',
  'arch_gateway': 'Gateway',
  'arch_l1_d': 'Botão Entrar',
  'arch_l2_d': 'Login Asodya',
  'arch_l3_d': 'Token de uso único',
  'arch_l4_d': 'Cookies da sessão',
  'arch_l5_d': 'Papel e projetos',
  'arch_s7_t': 'Acesso',
  'arch_s7_s': 'Três respostas para cada cartão',
  'arch_s7_p1': 'As rotas públicas não recebem identidade do gateway. As rotas de sessão recebem o id do usuário e o nível de acesso.',
  'arch_s7_p2': 'O motor confia no nível de acesso só junto com o id do usuário. Os administradores de projeto vêm da tabela de papéis, nunca de um cabeçalho.',
  'arch_s7_p3': 'As permissões abrem um relatório ou cartão para um usuário, um papel ou todos os usuários com login.',
  'arch_th_state': 'Estado',
  'arch_th_result': 'O que o leitor recebe',
  'arch_a_readable': 'Legível',
  'arch_a_readable_d': 'Linhas e gráficos',
  'arch_a_disc': 'Visível',
  'arch_a_disc_d': 'O título e um esqueleto com botão de login',
  'arch_a_hidden': 'Oculto',
  'arch_a_hidden_d': 'Não encontrado (404), sem rastro',
  'arch_s8_t': 'Frontend',
  'arch_s8_s': 'Um único código Flutter',
  'arch_s8_p1': 'A interface usa Flutter para a web. Cada projeto tem um tema claro e um escuro vindos da API.',
  'arch_s8_p2': 'Toda página tem texto em inglês, português e tailandês. Os dados de projeto do catálogo Asodya ficam no idioma do catálogo.',
  'arch_s8_p3': 'O navegador gera os arquivos de exportação a partir da API de conjuntos de dados. O servidor não processa arquivos.',
  'arch_v_line': 'Série temporal',
  'arch_v_bar': 'Barras',
  'arch_v_rank': 'Ranking',
  'arch_v_donut': 'Rosca',
  'arch_v_map': 'Mapa',
  'arch_v_table': 'Tabela',
  'arch_s9_t': 'API e telemetria',
  'arch_s9_s': 'Rotas documentadas, falhas reportadas',
  'arch_s9_p1': 'O motor gera seu documento OpenAPI a partir do código, então o documento fica sempre atual.',
  'arch_s9_p2': 'Toda rota começa com https://api.asodya.com/apps/reports/v1.',
  'arch_s9_p3': 'Cada chamada com falha da interface para outro serviço vai para a telemetria compartilhada de erros do gateway, sem tokens nem linhas.',
  'arch_th_route': 'Rota',
  'arch_th_access': 'Acesso',
  'arch_r_public': 'Público',
  'arch_r_session': 'Sessão',
  'arch_r_admin': 'Administrador',
  'asodya_logo': 'Logotipo da Asodya', 

  // Authentication.
  'auth_signing_in': 'Abrindo seus relatórios',
  'auth_signing_in_text': 'Aguarde. Estamos verificando sua sessão Asodya.',
  'auth_sync_failed': 'Não foi possível abrir seus relatórios',
  
  
  
  
  
  
  
  
  
  
  
  'auth_go_home': 'Ir para a página inicial',
  
  'auth_session_ended_text': 'Sua sessão Asodya terminou. Os relatórios públicos continuam abertos. Entre novamente para ver seus outros relatórios.', 
  
  'auth_log_out': 'Sair',
  'auth_role_super_admin': 'Superadministrador',
  'sign_in': 'Entrar',
  'access_tag_members': 'Membros',
  'access_tag_admin': 'Admin',
  'access_tag_members_count': '{n} gráficos de membros',
  'access_tag_admin_count': '{n} gráficos de admin',
  'access_tag_members_hint': 'Qualquer conta Asodya conectada pode abrir',
  'access_tag_admin_hint': 'Só o administrador do projeto ou quem tem acesso pode abrir',
  'show_more': 'Mostrar mais',
  'show_less': 'Mostrar menos',
  'sign_up': 'Criar conta',
  'tier_all': 'Todos',
  'tier_filter': 'Dados',
  'gated_login_text': 'Abre depois que você entrar',
  'gated_admin_text': 'Precisa de acesso do administrador do projeto',
  'guest_prompt_title': 'Veja mais dashboards com uma conta',
  'guest_prompt_locked_title': '{n} gráficos deste relatório abrem com uma conta',
  'guest_prompt_text': 'Os relatórios públicos continuam abertos. Entre ou crie uma conta Asodya gratuita para abrir os relatórios que precisam de uma.',
  'share': 'Compartilhar',
  'share_title': 'Compartilhar este gráfico',
  'share_text': 'O link abre este gráfico na visão completa, com o mesmo tipo de gráfico, visão e filtros.',
  'share_copy': 'Copiar link',
  'share_copied': 'Link copiado',
  'pub_nav_architecture': 'Arquitetura',
  'architecture_title': 'Arquitetura do Sistema',
  'architecture_subtitle': 'Topologia e pipeline de dados da plataforma analítica Reports',
  'auth_role_project_admin': 'Administrador do projeto',
  'auth_role_viewer': 'Visualizador',
  'auth_role_service': 'Serviço',

  // Public navigation and catalog.
  'pub_nav_overview': 'Visão geral',
  'pub_nav_projects': 'Projetos',
  'pub_nav_science': 'Ciência',
  'pub_nav_contact': 'Fale conosco',
  'pub_nav_reports': 'Reports',
  'pub_nav_label': 'Navegação do site',
  'pub_nav_open_menu': 'Abrir menu do site',
  'pub_nav_close_menu': 'Fechar menu do site',
  'pub_company_fallback': 'Reports',
  'pub_footer_company': 'Empresa',
  'pub_footer_all_projects': 'Todos os projetos',
  'pub_footer_contact_page': 'Página de contato',
  'pub_topic_de': 'Engenharia de dados',
  'pub_topic_ds': 'Ciência de dados',
  'pub_topic_ml': 'Aprendizado de máquina',
  'pub_topic_dl': 'Aprendizado profundo',
  'pub_topic_st': 'Estatística',
  'pub_home_eyebrow': 'Plataforma de relatórios',
  'pub_home_title': 'Uma camada analítica para cada projeto',
  'pub_home_lead': 'Relatórios, estatísticas e dashboards dos projetos Asodya: Certifications, Cortex, Asodya, AutoDroid e FSM.', 
  'pub_home_cta_projects': 'Explorar os projetos',
  'pub_flow_sources': 'Fontes',
  'pub_flow_sources_d': 'Registros dos projetos Asodya', 
  'pub_flow_ingest': 'Ingestão',
  'pub_flow_ingest_d': 'Validação do esquema em cada registro',
  'pub_flow_lake': 'Registros de relatórios',
  'pub_flow_lake_d': 'Registros versionados em um único armazenamento',
  'pub_flow_models': 'Modelos',
  'pub_flow_models_d': 'Estatísticas e cálculos publicados', 
  'pub_flow_reports': 'Relatórios',
  'pub_flow_reports_d': 'Gráficos, tabelas e exportações',
  'pub_home_projects_title': 'Nossos projetos',
  'pub_home_projects_intro':
      'As aplicações Asodya publicam análises confiáveis em um único catálogo de Reports. Cada aplicação mantém seu próprio limite de dados.',
  'pub_project_label': 'Projeto',
  'pub_visit_website': 'Visitar o site',
  'pub_learn_more': 'Saiba mais',
  'pub_read_more': 'Leia mais',
  'pub_home_science_title': 'Do dado bruto à decisão',
  'pub_home_science_intro': 'Cinco áreas de trabalho transformam os registros dos projetos em relatórios. Cada página explica os métodos e a matemática por trás deles.', 
  'pub_topic_de_short':
      'Colete, valide e armazene os dados de cada projeto em um único formato.',
  'pub_topic_ds_short':
      'Explore os dados, encontre padrões e meça o que importa.',
  'pub_topic_ml_short': 'Treine modelos que aprendem com exemplos rotulados.',
  'pub_topic_dl_short': 'Use redes neurais que aprendem suas próprias características.', 
  'pub_topic_st_short':
      'Meça a incerteza, compare resultados e teste previsões.',
  'pub_home_data_eyebrow': 'Engenharia de dados',
  'pub_home_data_title': 'Todo registro chega no mesmo formato de lote',
  'pub_home_data_text': 'Cada projeto envia seus registros para a API de ingestão do Reports. O caminho informa o projeto e o esquema; o lote informa a versão do esquema. A barreira rejeita campos ausentes, tipos incorretos e campos desconhecidos, então cada relatório lê registros limpos e versionados.',
  'pub_home_data_p1': 'Esquemas versionados com campos aninhados',
  'pub_home_data_p2': 'Um lote armazena todos os registros ou nenhum',
  'pub_home_data_p3':
      'Os relatórios calculam no servidor e enviam somente os dados',
  'pub_stat_projects': 'Projetos no catálogo',
  'pub_stat_languages': 'Idiomas em cada relatório',
  'pub_stat_fields': 'Áreas de trabalho com dados',
  'pub_stat_api': 'API de ingestão para cada produtor',
  'pub_cta_title': 'Dê o próximo passo',
  'pub_cta_text':
      'Abra os relatórios de um projeto ou fale com a equipe da plataforma.',
  'pub_cta_reports_title': 'Abrir os relatórios',
  'pub_cta_reports_text':
      'Gráficos, tabelas e exportações de todos os projetos',
  'pub_cta_contact_text': 'Dúvidas, acesso e parcerias',
  'pub_projects_title': 'Cinco projetos, uma camada de relatórios', 
  'pub_projects_lead': 'Certifications, Cortex, Asodya, AutoDroid e FSM publicam seus relatórios pelo Reports. Cada relatório mostra a origem dos seus dados.', 
  
  'pub_facts_title': 'No catálogo',
  
  'pub_fact_colors': 'Cores do tema',
  'pub_fact_none': 'Ainda não disponível',
  'pub_methods_title': 'Como o Reports funciona', 
  'pub_methods_intro': 'Os dados mudam de projeto para projeto. O método continua o mesmo.', 
  
  
  
  
  
  
  
  

  // Science pages.
  'pub_sci_title': 'A ciência por trás dos relatórios',
  'pub_sci_lead':
      'Engenharia de dados, ciência de dados, aprendizado de máquina, aprendizado profundo e estatística trabalham juntos em cada projeto. Aqui estão os métodos e a matemática.',
  'pub_sci_topics_title': 'Cinco áreas de trabalho',
  'pub_sci_math_title': 'A matemática em um só lugar',
  'pub_sci_math_intro': 'Cada fórmula leva à página que a explica.',
  'pub_sci_ideas': 'Ideias principais',
  'pub_sci_math': 'A matemática',
  'pub_sci_in_projects': 'Em nossos projetos',
  'pub_sci_next': 'Próximo tema: {name}',
  'pub_sci_illustration': 'Ilustração, não são dados reais',
  'pub_sci_topic_nav': 'Temas de ciência',
  'pub_chart_records': 'Registros por dia',
  'pub_chart_scatter': 'Duas medidas e uma linha ajustada',
  'pub_chart_loss': 'Perda de treinamento e validação',
  'pub_chart_train': 'Treinamento',
  'pub_chart_val': 'Validação',
  'pub_chart_net': 'Uma pequena rede neural',
  'pub_layer_in': 'Entrada',
  'pub_layer_hidden': 'Oculta',
  'pub_layer_out': 'Saída',
  'pub_chart_bell': 'Uma distribuição normal',
  'pub_sci_de_lead': 'A engenharia de dados leva os dados dos projetos aos relatórios. Ela coleta, verifica, armazena e prepara cada registro, para que a análise possa confiar nele.', 
  'pub_sci_de_p1_t': 'Envie, não busque',
  'pub_sci_de_p1_d':
      'Cada produtor envia seus dados com sua própria chave. O sistema sabe quais fontes enviam dados e quais estão silenciosas.',
  'pub_sci_de_p2_t': 'Esquemas com versões',
  'pub_sci_de_p2_d':
      'Um registro de esquemas mantém cada versão de cada formato de registro. A barreira valida cada registro contra sua versão.',
  'pub_sci_de_p3_t': 'Uma tabela longa',
  'pub_sci_de_p3_d': 'Os registros de todos os projetos usam o mesmo formato: uma chave de idempotência, o horário do evento e o payload de uma versão de esquema. Uma nova métrica não precisa de nova tabela.',
  'pub_sci_de_projects': 'A telemetria do Cortex, os jobs do AutoDroid, os itens de mídia do FSM, as tentativas do Certifications e as métricas do catálogo Asodya chegam pela mesma API de ingestão.', 
  'pub_sci_de_code_t': 'Um lote de ingestão',
  'pub_sci_de_code_d': 'Um registro telemetry_event do Cortex na versão 1 do esquema. A mesma chave de idempotência nunca grava um registro duas vezes.',
  'pub_f_lag': 'Atualidade dos dados',
  'pub_f_lag_d': 'O atraso entre um evento na origem e sua chegada ao Reports.', 
  'pub_f_pass': 'Taxa de aprovação',
  'pub_f_pass_d': 'A parcela de registros que passa pela barreira.',
  'pub_f_rollup': 'Consolidação por hora',
  'pub_f_rollup_d': 'A soma de todos os valores dentro de uma hora.',
  'pub_sci_ds_lead':
      'A ciência de dados faz perguntas aos dados. Ela explora, limpa, agrupa e mede, depois mostra a resposta como um gráfico que uma pessoa consegue ler.',
  'pub_sci_ds_p1_t': 'Explore primeiro',
  'pub_sci_ds_p1_d':
      'Distribuições, valores atípicos e lacunas mostram o que os dados podem responder e o que não podem.',
  'pub_sci_ds_p2_t': 'Agregue com cuidado',
  'pub_sci_ds_p2_d':
      'Somas, médias, proporções e listas principais dependem do agrupamento correto. O mecanismo calcula tudo no servidor.',
  'pub_sci_ds_p3_t': 'Encontre relações',
  'pub_sci_ds_p3_d':
      'Correlação e regressão mostram como duas medidas variam juntas. Elas não provam uma causa.',
  'pub_sci_ds_projects': 'Tokens por dia, taxa de falha por adaptador, armazenamento por aplicação e taxa de aprovação por certificação viram tabelas e gráficos.', 
  'pub_f_mean': 'Média',
  'pub_f_mean_d': 'O centro dos valores.',
  'pub_f_std': 'Desvio padrão',
  'pub_f_std_d': 'O quanto os valores se espalham em torno da média.',
  'pub_f_pearson': 'Correlação de Pearson',
  'pub_f_pearson_d':
      'A intensidade com que duas medidas variam juntas, de -1 a 1.',
  'pub_f_ols': 'Mínimos quadrados',
  'pub_f_ols_d':
      'A linha que se ajusta aos pontos com o menor erro quadrático.',
  'pub_sci_ml_lead':
      'O aprendizado de máquina treina modelos com exemplos rotulados. Um modelo aprende uma regra a partir dos dados e depois a aplica a novos dados.',
  'pub_sci_ml_p1_t': 'Rótulos e divisões',
  'pub_sci_ml_p1_d':
      'Exemplos rotulados entram nos conjuntos de treinamento, validação e teste. O modelo só vê o conjunto de teste no final.',
  'pub_sci_ml_p2_t': 'Perda e gradientes',
  'pub_sci_ml_p2_d':
      'Uma função de perda mede o erro. A descida do gradiente muda os pesos um pouco a cada passo para diminuir a perda.',
  'pub_sci_ml_p3_t': 'Registro e aprovação',
  'pub_sci_ml_p3_d':
      'Cada execução de treinamento recebe um registro. Uma pessoa aprova um modelo antes que ele se torne o modelo ativo.',
  'pub_sci_ml_projects': 'O Cortex envia cada requisição a um modelo por qualidade e custo. O Reports mede o resultado: latência, tokens e taxa de sucesso de cada modelo.', 
  'pub_sci_ml_code_t':
      'Uma configuração de treinamento e um ciclo de treinamento',
  'pub_sci_ml_code_d':
      'A configuração identifica os dados, o modelo e as definições de treinamento. O ciclo calcula a perda, os gradientes e a atualização.',
  'pub_f_sigmoid': 'Sigmoide',
  'pub_f_sigmoid_d':
      'Transforma uma pontuação em uma probabilidade entre 0 e 1.',
  'pub_f_softmax': 'Softmax',
  'pub_f_softmax_d':
      'Transforma K pontuações em K probabilidades cuja soma é 1.',
  'pub_f_ce': 'Entropia cruzada',
  'pub_f_ce_d':
      'A perda de um classificador. Ela é pequena quando a classe correta recebe uma probabilidade alta.',
  'pub_f_gd': 'Descida do gradiente',
  'pub_f_gd_d':
      'Cada passo move os pesos contra o gradiente, usando a taxa de aprendizado η.',
  'pub_f_f1': 'Pontuação F1',
  'pub_f_f1_d': 'O equilíbrio entre precisão P e revocação R.',
  'pub_sci_dl_lead': 'O deep learning usa redes neurais com muitas camadas. As redes aprendem suas próprias características a partir de entradas brutas, como texto ou pixels.', 
  'pub_sci_dl_p1_t': 'Convoluções enxergam padrões',
  'pub_sci_dl_p1_d': 'Pequenos filtros deslizam sobre a entrada. As primeiras camadas veem padrões simples. As camadas seguintes os combinam em formas maiores.', 
  'pub_sci_dl_p2_t': 'A detecção desenha caixas',
  'pub_sci_dl_p2_d':
      'Um detector fornece uma caixa, uma classe e uma confiança para cada objeto. A sobreposição com a caixa real mede a qualidade.',
  'pub_sci_dl_p3_t': 'Embeddings fazem comparações',
  'pub_sci_dl_p3_d':
      'Uma rede transforma uma imagem em um vetor. Imagens semelhantes geram vetores que apontam para a mesma direção.',
  'pub_sci_dl_projects': 'O Cortex usa grandes modelos de linguagem para chat, código e pesquisa. O Reports compara esses modelos com os mesmos campos de telemetria.', 
  'pub_f_relu': 'ReLU',
  'pub_f_relu_d': 'Mantém valores positivos e define os negativos como zero.',
  'pub_f_conv': 'Convolução',
  'pub_f_conv_d': 'Um filtro K desliza sobre a imagem I.',
  'pub_f_iou': 'Interseção sobre união',
  'pub_f_iou_d': 'O quanto uma caixa prevista A cobre a caixa real B.',
  'pub_f_cos': 'Similaridade cosseno',
  'pub_f_cos_d': 'Compara dois embeddings pela direção deles.',
  'pub_sci_st_lead':
      'A estatística mede a incerteza. Ela mostra o quanto um resultado é confiável, compara grupos e testa uma previsão contra o que realmente aconteceu.',
  'pub_sci_st_p1_t': 'Distribuições',
  'pub_sci_st_p1_d':
      'Uma distribuição descreve todos os valores que uma medida pode assumir e com que frequência cada valor aparece.',
  'pub_sci_st_p2_t': 'Probabilidades se atualizam',
  'pub_sci_st_p2_d': 'A regra de Bayes atualiza uma crença quando chega uma nova evidência, por exemplo um novo lote de registros.', 
  'pub_sci_st_p3_t': 'Previsões recebem pontuações',
  'pub_sci_st_p3_d':
      'Backtests comparam previsões antigas com o resultado real. As pontuações mostram acertos, falsos alarmes e calibração.',
  'pub_sci_st_projects': 'Uma média móvel de 7 dias suaviza a taxa de sucesso diária do Cortex, para que um dia ruim não esconda a tendência.', 
  'pub_f_normal': 'Distribuição normal',
  'pub_f_normal_d': 'A curva em sino com média μ e dispersão σ.',
  'pub_f_bayes': 'Regra de Bayes',
  'pub_f_bayes_d': 'Atualiza a probabilidade de A depois que B é observado.',
  'pub_f_kl': 'Divergência KL',
  'pub_f_kl_d': 'O quanto uma distribuição Q difere de uma distribuição P.',
  'pub_f_brier': 'Pontuação de Brier',
  'pub_f_brier_d':
      'O erro de previsões probabilísticas. Uma pontuação 0 é perfeita.',

  // Contact and API pages.
  'pub_contact_title': 'Fale com a equipe',
  'pub_contact_lead': 'Pergunte sobre um projeto ou sobre o acesso aos relatórios. Entre em um grupo da comunidade Asodya.', 
  
  
  'pub_contact_address': 'Endereço',
  'pub_contact_phone': 'Telefone',
  'pub_contact_email': 'E-mail',
  'pub_contact_social': 'Grupos da comunidade', 
  'pub_contact_projects_title': 'Links dos projetos', 
  'pub_contact_projects_intro': 'Cada projeto tem seu site ou seu repositório.', 
  'pub_contact_none': 'Os dados de contato ainda não estão disponíveis.',
  'pub_nav_api': 'API',
  
  
  'pub_api_openapi': 'Arquivo OpenAPI',
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  'pub_home_api_title': 'Baseie-se nos mesmos dados',
  'pub_home_api_text':
      'Os relatórios leem uma API documentada. Sua aplicação também pode lê-la, com os mesmos campos, unidades e filtros.',
  'pub_home_api_more': 'Saiba mais sobre a API',
  'pub_footer_developers': 'Desenvolvedores',

  // Report and layout controls.
  'open_sidebar': 'Abrir a barra lateral',
  'close_sidebar': 'Fechar a barra lateral',
  'switch_to_light': 'Mudar para o modo claro',
  'switch_to_dark': 'Mudar para o modo escuro',
  'breadcrumb': 'Trilha de navegação',
  'rows_by_report': 'Linhas por relatório',
  'charts_per_report': 'Gráficos por relatório',
  'rows_per_day': 'Linhas por dia',
  'more_reports': '+ {n} a mais',
  'date_range': '{start} a {end}',
  'no_website': 'Ainda não há site',
  'carousel_view': 'Visualização em carrossel',
  'previous_project': 'Projetos anteriores',
  'next_project': 'Próximos projetos',
  'go_to_project': 'Ir para o projeto {n}',
  'no_reports_detail': 'Este projeto não tem relatórios no momento.',
  'grid_view': 'Visualização em grade',
  'list_view': 'Visualização em lista',
  'search_reports': 'Pesquisar relatórios',
  'page_of': 'Página {page} de {pages}',
  'section': 'Seção {n}',
  'section_one': 'Seção um',
  'section_two': 'Seção dois',
  'section_three': 'Seção três',
  'section_four': 'Seção quatro',
  'section_five': 'Seção cinco',
  'section_six': 'Seção seis',
  'section_seven': 'Seção sete',
  'section_eight': 'Seção oito',
  'section_nine': 'Seção nove',
  'section_ten': 'Seção dez',
  'section_eleven': 'Seção onze',
  'section_twelve': 'Seção doze',
  'artifacts': 'Artefatos',
  'artifact_pdf': 'Relatório PDF',
  'artifact_pdf_hint': 'Gráficos e tabelas curtas em páginas A4',
  'artifact_md': 'Markdown',
  'artifact_md_hint': 'Textos e tabelas curtas',
  'artifact_csv': 'Dados CSV (ZIP)',
  'artifact_csv_hint': 'Todos os dados dos gráficos, um arquivo por gráfico',
  'export_preparing': 'Preparando',
  'export_loading': 'Carregando dados do gráfico {i} de {n}',
  'export_building': 'Criando o arquivo',
  'export_drawing': 'Desenhando o gráfico {i} de {n}',
  'md_rows_note': '{shown} de {total} linhas. O CSV contém todas as linhas.',
  'pdf_contents': 'Conteúdo',
  'pdf_language_note':
      'Português do Brasil. Os valores em outros idiomas são exibidos como imagens.',
  'filter_from': 'a partir de {v}',
  'filter_to': 'até {v}',
  'download_md': 'Baixar como Markdown',
  'download_pdf': 'Baixar como PDF',
  'reset_layout': 'Redefinir layout',
  'card_menu': 'Opções do card',
  'info': 'Informações',
  'minimize': 'Minimizar',
  'restore': 'Restaurar',
  'minimized': 'Minimizado',
  'move': 'Mover',
  'show_table': 'Mostrar como tabela',
  'show_chart': 'Mostrar como gráfico',
  'share_of': '{share} de {name}',
  'drop': 'Soltar',
  'arrange_hint':
      'Arraste um card para movê-lo. Arraste uma borda para redimensioná-lo. Soltar sobre outro card troca os dois.',
  'edit_layout': 'Editar layout',
  'rename_section': 'Renomear seção',
  'section_name_hint': 'Nome da seção',
  'section_name_taken':
      'Este nome já é usado neste relatório (maiúsculas e minúsculas contam como iguais).',
  'section_name_too_long': 'Use no máximo 32 caracteres.',
  'save': 'Salvar',
  'editing_layout': 'Editando layout',
  'done': 'Concluído',
  'cancel': 'Cancelar',
  'drop_here': 'Células livres',
  'resize_corner': 'Arraste para alterar o tamanho',
  'drag': 'Arrastar',
  'resize_width': 'Arraste para alterar a largura',
  'resize_height': 'Arraste para alterar a altura',
  'equation': 'Equação',
  'description': 'Descrição',
  'close': 'Fechar',
  'other': 'Outro',
  'rows_shown': '{shown} de {total} linhas',
  'rows_range': 'Linhas {from} a {to} de {total}',
  'filters': 'Filtros',
  'reset_filters': 'Redefinir',
  'all': 'Todos',
  'from': 'De',
  'to': 'Até',
  'apply': 'Aplicar',
  'search': 'Pesquisar',
  'selected_count': '{n} selecionados',
  'loading': 'Carregando',
  'error_loading': 'Não foi possível carregar os dados.',
  'retry': 'Tentar novamente',
  'not_found': 'Esta página não existe.',
  'back_to_menu': 'Voltar ao menu',
  'access_login_title': 'Entre para abrir este relatório',
  'access_login_detail': 'Este conteúdo precisa de uma conta Asodya. Os relatórios públicos continuam abertos sem conta.',
  'access_limited_title': 'Acesso limitado',
  'access_limited_detail': 'Sua conta não pode abrir este conteúdo. Um administrador do projeto pode liberar o acesso.',
  'auth_error_exchange': 'O link de entrada já foi usado, expirou ou não é válido. Sua sessão não foi aberta. Entre novamente.',
  'auth_sign_in_again': 'Entrar novamente',
  'pub_project_repository': 'Repositório',
  'pub_fact_status': 'Status',
  'pub_fact_collaborators': 'Contribuidores',
  'pub_domain_stale': 'Detalhes do projeto do catálogo Asodya de {time}. O catálogo não responde agora.',
  'pub_method_schemas_t': 'Esquemas versionados',
  'pub_method_schemas_d': 'Cada projeto registra o formato dos seus registros. Uma versão publicada nunca muda, e cada registro guarda sua versão.',
  'pub_method_calculations_t': 'Cálculos por definição',
  'pub_method_calculations_d': 'Contagens, somas, taxas, intervalos de tempo e janelas móveis vêm de definições publicadas. Nenhum projeto precisa de um serviço próprio.',
  'pub_method_access_t': 'Acesso por cartão',
  'pub_method_access_d': 'Um cartão é público, exige entrada ou é restrito. Visitantes veem gráficos públicos; gráficos protegidos mostram um espaço reservado sem dados.',
  'pub_method_exports_t': 'Exportação no navegador',
  'pub_method_exports_d': 'Arquivos PDF, Markdown e CSV ZIP são gerados no navegador, apenas com os dados que seu acesso permite.',
};
