using PowerModels
using Ipopt
using Printf

println("="^70)
println("ETAPA 1: CASO BASE (IEEE 14 BARRAS - REDE PURA)")
println("="^70)

caminho = joinpath(pkgdir(PowerModels), "test/data/matpower/case14.m")
rede_base = parse_file(caminho)
res_base = solve_ac_opf(rede_base, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))

custo_base = res_base["objective"]
v_min_base = minimum([b["vm"] for (_, b) in res_base["solution"]["bus"]])
v_max_base = maximum([b["vm"] for (_, b) in res_base["solution"]["bus"]])

@printf("Status: %s\n", res_base["termination_status"])
@printf("Custo Base: \$ %.2f /h\n", custo_base)
@printf("Tensão Mínima Base: %.4f pu | Tensão Máxima Base: %.4f pu\n\n", v_min_base, v_max_base)


println("="^70)
println("ETAPA 2: DATA CENTER COM CARGA ESTÁTICA (BARRA 14)")
println("="^70)

rede_estatica = deepcopy(rede_base)
for (_, b) in rede_estatica["bus"]
    b["vmin"] = 0.95
    b["vmax"] = 1.05
end

p_dc_estatico = 1.25 * 0.25 
q_dc_estatico = 0.0822

novo_id_estatica = string(length(rede_estatica["load"]) + 1)
rede_estatica["load"][novo_id_estatica] = Dict{String, Any}(
    "load_bus" => 14,
    "pd"       => p_dc_estatico,
    "qd"       => q_dc_estatico,
    "status"   => 1,
    "index"    => parse(Int, novo_id_estatica)
)

res_estatica = solve_ac_opf(rede_estatica, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
@printf("Custo com Data Center Estático: \$ %.2f /h\n", res_estatica["objective"])
@printf("Tensão na Barra 14 (Estático):   %.4f pu\n\n", res_estatica["solution"]["bus"]["14"]["vm"])


println("="^70)
println("ETAPA 3: DATA CENTER COM DEMANDA ESTOCÁSTICA / VARIÁVEL")
println("="^70)

p_it_nominal = 0.25
pue = 1.25
q_base = 0.0822
fatores_estocasticos = [0.90, 0.95, 1.00, 1.05, 1.10]

@printf("%-10s | %-12s | %-20s | %-16s\n", "Cenário", "Fator", "Custo Total (USD/h)", "Tensão Barra 14")
println("-"^70)

for (i, f) in enumerate(fatores_estocasticos)
    rede_estocastica = deepcopy(rede_base)
    for (_, b) in rede_estocastica["bus"]
        b["vmin"] = 0.95
        b["vmax"] = 1.05
    end
    
    p_dc = pue * (p_it_nominal * f)
    q_dc = q_base * f
    
    load_id_estocastica = string(length(rede_estocastica["load"]) + 1)
    rede_estocastica["load"][load_id_estocastica] = Dict{String, Any}(
        "load_bus" => 14, 
        "pd"       => p_dc, 
        "qd"       => q_dc, 
        "status"   => 1, 
        "index"    => parse(Int, load_id_estocastica)
    )
    
    sol = solve_ac_opf(rede_estocastica, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
    if sol["termination_status"] == LOCALLY_SOLVED
        @printf("Cenário %-2d | %-12.2f | \$ %.2f          | %.4f pu\n", i, f, sol["objective"], sol["solution"]["bus"]["14"]["vm"])
    end
end
println("="^70)

#This is Ipopt version 3.14.19, running with linear solver MUMPS 5.9.0.

#Number of nonzeros in equality constraint Jacobian...:      492
#Number of nonzeros in inequality constraint Jacobian.:       40
#Number of nonzeros in Lagrangian Hessian.............:      806

#Total number of variables............................:      118
#                     variables with only lower bounds:        0
#                variables with lower and upper bounds:       24
#                     variables with only upper bounds:        0
#Total number of equality constraints.................:      109
#Total number of inequality constraints...............:       20
#        inequality constraints with only lower bounds:        0
#   inequality constraints with lower and upper bounds:       20
#        inequality constraints with only upper bounds:        0

#iter    objective    inf_pr   inf_du lg(mu)  ||d||  lg(rg) alpha_du alpha_pr  ls
#   0  1.6032287e+02 9.32e-01 1.58e+01  -1.0 0.00e+00    -  0.00e+00 0.00e+00   0
#   1  8.7192502e+03 2.03e-02 6.69e+01  -1.0 7.76e-01    -  1.44e-02 1.00e+00h  1
#   2  8.0213421e+03 2.43e-02 2.37e+01  -1.0 1.04e+00    -  6.31e-01 1.00e+00f  1
#   3  8.0955523e+03 4.88e-04 4.38e-01  -1.0 7.92e-02    -  1.00e+00 1.00e+00h  1
#   4  8.0881077e+03 3.17e-04 1.39e-02  -1.7 3.82e-02    -  1.00e+00 1.00e+00f  1
#   5  8.0847538e+03 2.09e-04 7.09e-01  -2.5 4.33e-02    -  7.88e-01 6.68e-01f  1
#   6  8.0818441e+03 2.87e-04 8.22e-03  -2.5 4.48e-02    -  1.00e+00 1.00e+00f  1
#   7  8.0815324e+03 5.66e-05 7.15e-03  -3.8 1.93e-02    -  9.38e-01 9.31e-01h  1
#...



#EXIT: Optimal Solution Found.
#Cenário 5  | 1.10         | $ 9571.19          | 0.9564 pu
#======================================================================


println("="*70)
println("ETAPA 4: VARREDURA NODAL (NODE SCANNING) PARA ALOCAÇÃO DO DATA CENTER")
println("="*70)

# Carrega a rede base (podes trocar por case118.m quando quiseres escalar para o sistema maior)
caminho = joinpath(pkgdir(PowerModels), "test/data/matpower/case14.m")
rede_base = parse_file(caminho)

# Identifica apenas as barras que são puramente de carga (bus_type == 1)
barras_carga = [parse(Int, id) for (id, b) in rede_base["bus"] if b["bus_type"] == 1]
resultados_alocacao = []

println("Iniciando varredura em $(length(barras_carga)) barras candidatas...")

for b_id in sort(barras_carga)
    rede_iter = deepcopy(rede_base)
    
    # Aplica os limites regulatórios brasileiros (0.95 a 1.05 pu)
    for (_, b) in rede_iter["bus"]
        b["vmin"] = 0.95
        b["vmax"] = 1.05
    end
    
    # Insere o Data Center com carga nominal (25 MW * PUE 1.25 = 31.25 MW) na barra atual da varredura
    p_dc_nominal = 1.25 * 0.25
    q_dc_nominal = 0.0822
    
    novo_id = string(length(rede_iter["load"]) + 1)
    rede_iter["load"][novo_id] = Dict{String, Any}(
        "load_bus" => b_id,
  "pd"       => p_dc_nominal,
        "qd"       => q_dc_nominal,
        "status"   => 1,
        "index"    => parse(Int, novo_id)
    )
    
    # Resolve o AC-OPF de forma silenciosa
    sol = solve_ac_opf(rede_iter, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
   if sol["termination_status"] == LOCALLY_SOLVED
        custo = sol["objective"]
        v_local = sol["solution"]["bus"][string(b_id)]["vm"]
        v_min_rede = minimum([b["vm"] for (_, b) in sol["solution"]["bus"]])
        push!(resultados_alocacao, (Barra=b_id, Custo=custo, V_local=v_local, V_min=v_min_rede))
    else
        push!(resultados_alocacao, (Barra=b_id, Custo=Inf, V_local=NaN, V_min=NaN))
    end
end

# Ordena do menor custo para o maior (ranking de impacto sistêmico)
sort!(resultados_alocacao, by = x -> x.Custo)

println("\n" * "="*70)
println("RANKING DE ALOCAÇÃO ÓTIMA DO DATA CENTER (25 MW)")
println("="*70)
@printf("%-8s | %-20s | %-16s | %-16s\n", "Barra", "Custo Total (USD/h)", "Tensão Local", "Tensão Mín. Rede")
println("-"*70)

for r in resultados_alocacao
    @printf("Barra %-2d | \$ %-18.2f | %.4f pu         | %.4f pu\n", r.Barra, r.Custo, r.V_local, r.V_min)
end
println("="^70)

#======================================================================
#ETAPA 4: VARREDURA NODAL (NODE SCANNING) PARA ALOCAÇÃO DO DATA CENTER
#======================================================================

#This is Ipopt version 3.14.19, running with linear solver MUMPS 5.9.0.

#Number of nonzeros in equality constraint Jacobian...:      492
#Number of nonzeros in inequality constraint Jacobian.:       40
#Number of nonzeros in Lagrangian Hessian.............:      806

#Total number of variables............................:      118
#                     variables with only lower bounds:        0
#                variables with lower and upper bounds:       24
#                     variables with only upper bounds:        0
#Total number of equality constraints.................:      109
#Total number of inequality constraints...............:       20
#        inequality constraints with only lower bounds:        0
#   inequality constraints with lower and upper bounds:       20
#        inequality constraints with only upper bounds:        0

#iter    objective    inf_pr   inf_du lg(mu)  ||d||  lg(rg) alpha_du alpha_pr  ls
#   0  1.6032287e+02 9.32e-01 1.58e+01  -1.0 0.00e+00    -  0.00e+00 0.00e+00   0
#   1  9.9110393e+03 2.75e-02 7.30e+01  -1.0 8.37e-01    -  1.33e-02 9.99e-01h  1
#   2  9.2973411e+03 2.00e-02 2.66e+01  -1.0 9.91e-01    -  6.20e-01 1.00e+00f  1
#   3  9.3613976e+03 4.27e-04 2.52e-01  -1.0 1.01e-01    -  1.00e+00 1.00e+00h  1
#   4  9.3582756e+03 9.23e-05 8.95e-03  -1.7 1.94e-02    -  1.00e+00 1.00e+00h  1
#   5  9.3545344e+03 2.85e-04 4.41e-02  -2.5 3.37e-02    -  8.13e-01 8.24e-01f  1
#   6  9.3530055e+03 1.55e-04 4.40e-03  -2.5 3.78e-02    -  1.00e+00 1.00e+00f  1
#...
#Barra 13 | $ 9390.52            | 1.0055 pu         | 1.0017 pu
#Barra 12 | $ 9404.46            | 0.9890 pu         | 0.9890 pu
#Barra 14 | $ 9430.99            | 0.9622 pu         | 0.9622 pu
#======================================================================

println("="^70)
println("ETAPA 5: MITIGAÇÃO DE IMPACTO COM BESS (PEAK SHAVING NA BARRA 14)")
println("="^70)

# 1. Carrega o IEEE 14 barras e define o cenário crítico de pico do Data Center (Fator 1.10)
caminho = joinpath(pkgdir(PowerModels), "test/data/matpower/case14.m")
rede_critica = parse_file(caminho)

for (_, b) in rede_critica["bus"]
    b["vmin"] = 0.95
    b["vmax"] = 1.05
end

p_it_nominal = 0.25
pue = 1.25
fator_pico = 1.10
q_base = 0.0822

p_dc_pico = pue * (p_it_nominal * fator_pico) # ~0.3437 MW
q_dc_pico = q_base * fator_pico

novo_id = string(length(rede_critica["load"]) + 1)
rede_critica["load"][novo_id] = Dict{String, Any}(
    "load_bus" => 14,
    "pd"       => p_dc_pico,
    "qd"       => q_dc_pico,
    "status"   => 1,
    "index"    => parse(Int, novo_id)
)

# Resolve o caso crítico sem BESS para termos a linha de base do problema
sol_sem_bess = solve_ac_opf(rede_critica, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
v_b14_sem_bess = sol_sem_bess["solution"]["bus"]["14"]["vm"]
custo_sem_bess = sol_sem_bess["objective"]

@printf("--- CENÁRIO CRÍTICO (SEM BESS) ---\n")
@printf("Custo Total: USD %.2f/h | Tensão Barra 14: %.4f pu\n\n", custo_sem_bess, v_b14_sem_bess)

# 2. Introdução do BESS para mitigação (Peak Shaving)
# O BESS descarrega potência ativa na mesma barra do Data Center (Barra 14) 
# para abater parte da demanda líquida exigida da rede de transmissão.
# Simulamos uma injeção de 5 MW (0.05 pu considerando base 100 MVA) de potência ativa pela bateria.

potencia_bess_mw = 0.05 # 5 MW de alívio via BESS

rede_com_bess = deepcopy(rede_critica)
# Subtraímos a potência descarregada pelo BESS da carga líquida vista pela rede
rede_com_bess["load"][novo_id]["pd"] = p_dc_pico - potencia_bess_mw

sol_com_bess = solve_ac_opf(rede_com_bess, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))

if sol_com_bess["termination_status"] == LOCALLY_SOLVED
    v_b14_com_bess = sol_com_bess["solution"]["bus"]["14"]["vm"]
    custo_com_bess = sol_com_bess["objective"]
    
    @printf("--- CENÁRIO COM MITIGAÇÃO BESS (5 MW de Descarga) ---\n")
    @printf("Custo Total: USD %.2f/h | Tensão Barra 14: %.4f pu\n", custo_com_bess, v_b14_com_bess)
    @printf("Melhoria na Tensão da Barra 14: +%.4f pu\n", v_b14_com_bess - v_b14_sem_bess)
else
    println("A otimização com BESS não convergiu.")
end
println("="^70)

#======================================================================
#ETAPA 5: MITIGAÇÃO DE IMPACTO COM BESS (PEAK SHAVING NA BARRA 14)
#======================================================================

#This is Ipopt version 3.14.19, running with linear solver MUMPS 5.9.0.

#Number of nonzeros in equality constraint Jacobian...:      492
#Number of nonzeros in inequality constraint Jacobian.:       40
#Number of nonzeros in Lagrangian Hessian.............:      806

#Total number of variables............................:      118
#                     variables with only lower bounds:        0
#                variables with lower and upper bounds:       24
#                     variables with only upper bounds:        0
#Total number of equality constraints.................:      109
#Total number of inequality constraints...............:       20
#        inequality constraints with only lower bounds:        0
#   inequality constraints with lower and upper bounds:       20
#        inequality constraints with only upper bounds:        0

#iter    objective    inf_pr   inf_du lg(mu)  ||d||  lg(rg) alpha_du alpha_pr  ls
#   0  1.6032287e+02 9.32e-01 1.58e+01  -1.0 0.00e+00    -  0.00e+00 0.00e+00   0
#   1  1.0034423e+04 3.07e-02 7.37e+01  -1.0 8.44e-01    -  1.31e-02 1.00e+00h  1
#   2  9.8385362e+03 2.75e-02 5.85e+01  -1.0 1.01e+00    -  6.28e-01 2.09e-01f  1
#   3  9.5518753e+03 8.45e-03 1.75e+01  -1.0 8.27e-01    -  1.00e+00 7.02e-01f  1
#   4  9.5694441e+03 1.74e-03 1.84e+00  -1.0 2.83e-01    -  1.00e+00 1.00e+00h  1
#   5  9.5768759e+03 3.09e-05 7.38e-02  -1.0 2.37e-02    -  1.00e+00 1.00e+00h  1
#   6  9.5740305e+03 8.36e-05 4.63e+00  -2.5 3.58e-02    -  9.28e-01 1.00e+00f  1
#   7  9.5722944e+03 3.41e-05 1.76e+00  -2.5 3.91e-02    -  6.38e-01 1.00e+00f  1
#...
#--- CENÁRIO COM MITIGAÇÃO BESS (5 MW de Descarga) ---
#Custo Total: USD 9349.68/h | Tensão Barra 14: 0.9625 pu
#Melhoria na Tensão da Barra 14: +0.0061 pu
#======================================================================


#==================================================TESTE COM O SISTEMA IEEE 118 BARRAS=================================

using PowerModels
using Ipopt
using Printf
using Downloads

println("="^70)
println("ETAPA 1 & 2 (ESCALA 118 BARRAS): CASO BASE E DATA CENTER ESTÁTICO")
println("="^70)

# Baixa o arquivo case118.m
arquivo_118 = "case118.m"
if !isfile(arquivo_118)
    println("Baixando o sistema IEEE 118 do repositório oficial...")
    Downloads.download("https://raw.githubusercontent.com/MATPOWER/matpower/master/data/case118.m", arquivo_118)
    println("Download concluído com sucesso!")
end

# 1. Carrega o sistema de 118 barras local
rede_base_118 = parse_file(arquivo_118)

# Resolve o Caso Base para o IEEE 118
res_base_118 = solve_ac_opf(rede_base_118, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))

custo_base_118 = res_base_118["objective"]
v_min_base_118 = minimum([b["vm"] for (_, b) in res_base_118["solution"]["bus"]])
v_max_base_118 = maximum([b["vm"] for (_, b) in res_base_118["solution"]["bus"]])

@printf("Status do Caso Base (118): %s\n", res_base_118["termination_status"])
@printf("Custo Base (118): \$ %.2f /h\n", custo_base_118)
@printf("Tensão Mínima: %.4f pu | Tensão Máxima: %.4f pu\n\n", v_min_base_118, v_max_base_118)

# 2. Inserção do Data Center (Exemplo na Barra 118)
rede_estatica_118 = deepcopy(rede_base_118)
for (_, b) in rede_estatica_118["bus"]
    b["vmin"] = 0.95
    b["vmax"] = 1.05
end

p_dc_estatico = 1.25 * 0.25 
q_dc_estatico = 0.0822
barra_alvo = 118

novo_id_118 = string(length(rede_estatica_118["load"]) + 1)
rede_estatica_118["load"][novo_id_118] = Dict{String, Any}(
    "load_bus" => barra_alvo,
    "pd"       => p_dc_estatico,
    "qd"       => q_dc_estatico,
    "status"   => 1,
    "index"    => parse(Int, novo_id_118)
)

res_estatica_118 = solve_ac_opf(rede_estatica_118, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))

if res_estatica_118["termination_status"] == LOCALLY_SOLVED
    @printf("Custo com Data Center na Barra %d (118): \$ %.2f /h\n", barra_alvo, res_estatica_118["objective"])
    @printf("Tensão na Barra Alvo: %.4f pu\n", res_estatica_118["solution"]["bus"][string(barra_alvo)]["vm"])
    @printf("Tensão Mínima Global da Rede: %.4f pu\n", minimum([b["vm"] for (_, b) in res_estatica_118["solution"]["bus"]]))
else
    println("A otimização para o sistema de 118 barras não convergiu com os parâmetros atuais.")
end
println("="^70)

#======================================================================
#ETAPA 1 & 2 (ESCALA 118 BARRAS): CASO BASE E DATA CENTER ESTÁTICO
#======================================================================

#Custo com Data Center na Barra 118 (118): $ 130994.24 /h
#Tensão na Barra Alvo: 0.9913 pu
#Tensão Mínima Global da Rede: 0.9913 pu
#======================================================================

using PowerModels
using Ipopt
using Printf

println("="^70)
println("ETAPA 3 (ESCALA 118 BARRAS): DEMANDA ESTOCÁSTICA DO DATA CENTER")
println("="^70)

# Garante que esta sendo usada a base de 118 barras carregada anteriormente)
rede_base_118 = parse_file(arquivo_118)

p_it_nominal = 0.25
pue = 1.25
q_base = 0.0822
fatores_estocasticos = [0.90, 0.95, 1.00, 1.05, 1.10]
barra_alvo = 118 # Barra onde o Data Center está conectado no sistema de 118

@printf("%-10s | %-12s | %-22s | %-16s\n", "Cenário", "Fator", "Custo Total (USD/h)", "Tensão Barra 118")
println("-"^75)

for (i, f) in enumerate(fatores_estocasticos)
    rede_estocastica_118 = deepcopy(rede_base_118)
    for (_, b) in rede_estocastica_118["bus"]
        b["vmin"] = 0.95
        b["vmax"] = 1.05
    end
    
    p_dc = pue * (p_it_nominal * f)
    q_dc = q_base * f
    
    load_id = string(length(rede_estocastica_118["load"]) + 1)
    rede_estocastica_118["load"][load_id] = Dict{String, Any}(
        "load_bus" => barra_alvo, 
        "pd"       => p_dc, 
        "qd"       => q_dc, 
        "status"   => 1, 
        "index"    => parse(Int, load_id)
    )
    
    sol = solve_ac_opf(rede_estocastica_118, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
    if sol["termination_status"] == LOCALLY_SOLVED
        v_alvo = sol["solution"]["bus"][string(barra_alvo)]["vm"]
        @printf("Cenário %-2d | %-12.2f | \$ %-20.2f | %.4f pu\n", i, f, sol["objective"], v_alvo)
    end
end
println("="^75)

#======================================================================
#ETAPA 3 (ESCALA 118 BARRAS): DEMANDA ESTOCÁSTICA DO DATA CENTER
#======================================================================

#EXIT: Optimal Solution Found.
#Cenário 5  | 1.10         | $ 131122.61            | 0.9902 pu
#===========================================================================


println("="^70)
println("ETAPA 4 (ESCALA 118 BARRAS): VARREDURA NODAL PARA ALOCAÇÃO DO DATA CENTER")
println("="^70)

rede_base_118 = parse_file(arquivo_118)

# Identifica apenas as barras que são puramente de carga (bus_type == 1)
barras_carga = [parse(Int, id) for (id, b) in rede_base_118["bus"] if b["bus_type"] == 1]
resultados_alocacao = []

println("Iniciando varredura em $(length(barras_carga)) barras de carga candidatas...")

for b_id in sort(barras_carga)
    rede_iter = deepcopy(rede_base_118)
    
    # Aplica os limites regulatórios (0.95 a 1.05 pu)
    for (_, b) in rede_iter["bus"]
        b["vmin"] = 0.95
        b["vmax"] = 1.05
    end
    
    # Insere o Data Center com carga nominal (25 MW * PUE 1.25 = 31.25 MW) na barra atual
    p_dc_nominal = 1.25 * 0.25
    q_dc_nominal = 0.0822
    
    novo_id = string(length(rede_iter["load"]) + 1)
    rede_iter["load"][novo_id] = Dict{String, Any}(
        "load_bus" => b_id,
        "pd"       => p_dc_nominal,
        "qd"       => q_dc_nominal,
        "status"   => 1,
        "index"    => parse(Int, novo_id)
    )
    
    # Resolve o AC-OPF de forma silenciosa
    sol = solve_ac_opf(rede_iter, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
    
    if sol["termination_status"] == LOCALLY_SOLVED
        custo = sol["objective"]
        v_local = sol["solution"]["bus"][string(b_id)]["vm"]
        v_min_rede = minimum([b["vm"] for (_, b) in sol["solution"]["bus"]])
        push!(resultados_alocacao, (Barra=b_id, Custo=custo, V_local=v_local, V_min=v_min_rede))
    else
        push!(resultados_alocacao, (Barra=b_id, Custo=Inf, V_local=NaN, V_min=NaN))
    end
end

# Ordena do menor custo para o maior (ranking de impacto sistêmico)
sort!(resultados_alocacao, by = x -> x.Custo)

println("\n" * "="^70)
println("RANKING DE ALOCAÇÃO ÓTIMA DO DATA CENTER (25 MW) - IEEE 118")
println("="^70)
@printf("%-8s | %-22s | %-16s | %-16s\n", "Barra", "Custo Total (USD/h)", "Tensão Local", "Tensão Mín. Rede")
println("-"^70)

for r in resultados_alocacao
    @printf("Barra %-3d | \$ %-20.2f | %.4f pu         | %.4f pu\n", r.Barra, r.Custo, r.V_local, r.V_min)
end
println("="^75)

#======================================================================
#ETAPA 4 (ESCALA 118 BARRAS): VARREDURA NODAL PARA ALOCAÇÃO DO DATA CENTER
#======================================================================

#Barra 53  | $ 131017.89            | 0.9919 pu         | 0.9919 pu
#Barra 52  | $ 131019.06            | 0.9893 pu         | 0.9893 pu
#Barra 44  | $ 131024.01            | 0.9970 pu         | 0.9970 pu
#===========================================================================


println("="^70)
println("ETAPA 5: MITIGAÇÃO DE IMPACTO COM BESS (PEAK SHAVING NA BARRA 52)")
println("="^70)

# 1. Carrega o IEEE 14 barras e define o cenário crítico de pico do Data Center (Fator 1.10)
rede_critica = parse_file(arquivo_118)

for (_, b) in rede_critica["bus"]
    b["vmin"] = 0.95
    b["vmax"] = 1.05
end

p_it_nominal = 0.25
pue = 1.25
fator_pico = 1.10
q_base = 0.0822

p_dc_pico = pue * (p_it_nominal * fator_pico) # ~0.3437 MW
q_dc_pico = q_base * fator_pico

novo_id = string(length(rede_critica["load"]) + 1)
rede_critica["load"][novo_id] = Dict{String, Any}(
    "load_bus" => 52,
    "pd"       => p_dc_pico,
    "qd"       => q_dc_pico,
    "status"   => 1,
    "index"    => parse(Int, novo_id)
)

# Resolve o caso crítico sem BESS para termos a linha de base do problema
sol_sem_bess = solve_ac_opf(rede_critica, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
v_b52_sem_bess = sol_sem_bess["solution"]["bus"]["52"]["vm"]
custo_sem_bess = sol_sem_bess["objective"]

@printf("--- CENÁRIO CRÍTICO (SEM BESS) ---\n")
@printf("Custo Total: USD %.2f/h | Tensão Barra 52: %.4f pu\n\n", custo_sem_bess, v_b52_sem_bess)

# 2. Introdução do BESS para mitigação (Peak Shaving)
# O BESS descarrega potência ativa na mesma barra do Data Center (Barra 14) 
# para abater parte da demanda líquida exigida da rede de transmissão.
# Simulamos uma injeção de 5 MW (0.05 pu considerando base 100 MVA) de potência ativa pela bateria.

potencia_bess_mw = 0.05 # 5 MW de alívio via BESS

rede_com_bess = deepcopy(rede_critica)
# Subtraímos a potência descarregada pelo BESS da carga líquida vista pela rede
rede_com_bess["load"][novo_id]["pd"] = p_dc_pico - potencia_bess_mw

sol_com_bess = solve_ac_opf(rede_com_bess, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))

if sol_com_bess["termination_status"] == LOCALLY_SOLVED
    v_b52_com_bess = sol_com_bess["solution"]["bus"]["52"]["vm"]
    custo_com_bess = sol_com_bess["objective"]
    
    @printf("--- CENÁRIO COM MITIGAÇÃO BESS (5 MW de Descarga) ---\n")
    @printf("Custo Total: USD %.2f/h | Tensão Barra 52: %.4f pu\n", custo_com_bess, v_b52_com_bess)
    @printf("Melhoria na Tensão da Barra 52: +%.4f pu\n", v_b14_com_bess - v_b52_sem_bess)
else
    println("A otimização com BESS não convergiu.")
end
println("="^70)

#=====================================================================
#ETAPA 5: MITIGAÇÃO DE IMPACTO COM BESS (PEAK SHAVING NA BARRA 52)
#=====================================================================

#--- CENÁRIO COM MITIGAÇÃO BESS (5 MW de Descarga) ---
#Custo Total: USD 130940.83/h | Tensão Barra 52: 0.9891 pu
#Melhoria na Tensão da Barra 52: +0.0016 pu
#======================================================================
