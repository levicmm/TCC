using PowerModels
using Ipopt
using Printf
using Downloads

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
        @printf("Cenário %-2d | %-12.2f | \$ %.2f         | %.4f pu\n", i, f, sol["objective"], sol["solution"]["bus"]["14"]["vm"])
    end
end
println("="^70)


println("=" * 70)
println("ETAPA 4: VARREDURA NODAL (NODE SCANNING) PARA ALOCAÇÃO DO DATA CENTER")
println("=" * 70)

barras_carga = [parse(Int, id) for (id, b) in rede_base["bus"] if b["bus_type"] == 1]
resultados_alocacao = []

println("Iniciando varredura em $(length(barras_carga)) barras candidatas...")

for b_id in sort(barras_carga)
    rede_iter = deepcopy(rede_base)
    
    for (_, b) in rede_iter["bus"]
        b["vmin"] = 0.95
        b["vmax"] = 1.05
    end
    
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

sort!(resultados_alocacao, by = x -> x.Custo)

println("\n" * "="*70)
println("RANKING DE ALOCAÇÃO ÓTIMA DO DATA CENTER (25 MW)")
println("="*70)
@printf("%-8s | %-20s | %-16s | %-16s\n", "Barra", "Custo Total (USD/h)", "Tensão Local", "Tensão Mín. Rede")
println("-"^70)

for r in resultados_alocacao
    @printf("Barra %-2d | \$ %-18.2f | %.4f pu          | %.4f pu\n", r.Barra, r.Custo, r.V_local, r.V_min)
end
println("="^70)


println("="^70)
println("ETAPA 5: MITIGAÇÃO DE IMPACTO COM BESS (PEAK SHAVING NA BARRA 14)")
println("="^70)

rede_critica = parse_file(caminho)

for (_, b) in rede_critica["bus"]
    b["vmin"] = 0.95
    b["vmax"] = 1.05
end

p_it_nominal = 0.25
pue = 1.25
fator_pico = 1.10
q_base = 0.0822

p_dc_pico = pue * (p_it_nominal * fator_pico)
q_dc_pico = q_base * fator_pico

novo_id = string(length(rede_critica["load"]) + 1)
rede_critica["load"][novo_id] = Dict{String, Any}(
    "load_bus" => 14,
    "pd"       => p_dc_pico,
    "qd"       => q_dc_pico,
    "status"   => 1,
    "index"    => parse(Int, novo_id)
)

sol_sem_bess = solve_ac_opf(rede_critica, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
v_b14_sem_bess = sol_sem_bess["solution"]["bus"]["14"]["vm"]
custo_sem_bess = sol_sem_bess["objective"]

@printf("--- CENÁRIO CRÍTICO (SEM BESS) ---\n")
@printf("Custo Total: USD %.2f/h | Tensão Barra 14: %.4f pu\n\n", custo_sem_bess, v_b14_sem_bess)

potencia_bess_mw = 0.05 
rede_com_bess = deepcopy(rede_critica)
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


# ===================================================================
# SEÇÃO DO SISTEMA IEEE 118 BARRAS
# ===================================================================

println("="^70)
println("ETAPA 1 & 2 (ESCALA 118 BARRAS): CASO BASE E DATA CENTER ESTÁTICO")
println("="^70)

arquivo_118 = "case118.m"
if !isfile(arquivo_118)
    println("Baixando o sistema IEEE 118 do repositório oficial...")
    Downloads.download("https://raw.githubusercontent.com/MATPOWER/matpower/master/data/case118.m", arquivo_118)
    println("Download concluído com sucesso!")
end

rede_base_118 = parse_file(arquivo_118)
res_base_118 = solve_ac_opf(rede_base_118, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))

custo_base_118 = res_base_118["objective"]
v_min_base_118 = minimum([b["vm"] for (_, b) in res_base_118["solution"]["bus"]])
v_max_base_118 = maximum([b["vm"] for (_, b) in res_base_118["solution"]["bus"]])

@printf("Status do Caso Base (118): %s\n", res_base_118["termination_status"])
@printf("Custo Base (118): \$ %.2f /h\n", custo_base_118)
@printf("Tensão Mínima: %.4f pu | Tensão Máxima: %.4f pu\n\n", v_min_base_118, v_max_base_118)

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


println("="^70)
println("ETAPA 3 (ESCALA 118 BARRAS): DEMANDA ESTOCÁSTICA DO DATA CENTER")
println("="^70)

rede_base_118 = parse_file(arquivo_118)
p_it_nominal = 0.25
pue = 1.25
q_base = 0.0822
fatores_estocasticos = [0.90, 0.95, 1.00, 1.05, 1.10]
barra_alvo = 118

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


println("="^70)
println("ETAPA 4 (ESCALA 118 BARRAS): VARREDURA NODAL PARA ALOCAÇÃO DO DATA CENTER")
println("="^70)

rede_base_118 = parse_file(arquivo_118)
barras_carga = [parse(Int, id) for (id, b) in rede_base_118["bus"] if b["bus_type"] == 1]
resultados_alocacao = []

println("Iniciando varredura em $(length(barras_carga)) barras de carga candidatas...")

for b_id in sort(barras_carga)
    rede_iter = deepcopy(rede_base_118)
    
    for (_, b) in rede_iter["bus"]
        b["vmin"] = 0.95
        b["vmax"] = 1.05
    end
    
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

sort!(resultados_alocacao, by = x -> x.Custo)

println("\n" * "="^70)
println("RANKING DE ALOCAÇÃO ÓTIMA DO DATA CENTER (25 MW) - IEEE 118")
println("="^70)
@printf("%-8s | %-22s | %-16s | %-16s\n", "Barra", "Custo Total (USD/h)", "Tensão Local", "Tensão Mín. Rede")
println("-"^70)

for r in resultados_alocacao
    @printf("Barra %-3d | \$ %-20.2f | %.4f pu          | %.4f pu\n", r.Barra, r.Custo, r.V_local, r.V_min)
end
println("="^75)


println("="^70)
println("ETAPA 5: MITIGAÇÃO DE IMPACTO COM BESS (PEAK SHAVING NA BARRA 52)")
println("="^70)

rede_critica = parse_file(arquivo_118)

for (_, b) in rede_critica["bus"]
    b["vmin"] = 0.95
    b["vmax"] = 1.05
end

p_it_nominal = 0.25
pue = 1.25
fator_pico = 1.10
q_base = 0.0822

p_dc_pico = pue * (p_it_nominal * fator_pico)
q_dc_pico = q_base * fator_pico

novo_id = string(length(rede_critica["load"]) + 1)
rede_critica["load"][novo_id] = Dict{String, Any}(
    "load_bus" => 52,
    "pd"       => p_dc_pico,
    "qd"       => q_dc_pico,
    "status"   => 1,
    "index"    => parse(Int, novo_id)
)

sol_sem_bess = solve_ac_opf(rede_critica, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))
v_b52_sem_bess = sol_sem_bess["solution"]["bus"]["52"]["vm"]
custo_sem_bess = sol_sem_bess["objective"]

@printf("--- CENÁRIO CRÍTICO (SEM BESS) ---\n")
@printf("Custo Total: USD %.2f/h | Tensão Barra 52: %.4f pu\n\n", custo_sem_bess, v_b52_sem_bess)

potencia_bess_mw = 0.05 
rede_com_bess = deepcopy(rede_critica)
rede_com_bess["load"][novo_id]["pd"] = p_dc_pico - potencia_bess_mw

sol_com_bess = solve_ac_opf(rede_com_bess, Ipopt.Optimizer; setting = Dict("output" => Dict("print_level" => 0)))

if sol_com_bess["termination_status"] == LOCALLY_SOLVED
    v_b52_com_bess = sol_com_bess["solution"]["bus"]["52"]["vm"]
    custo_com_bess = sol_com_bess["objective"]
    
    @printf("--- CENÁRIO COM MITIGAÇÃO BESS (5 MW de Descarga) ---\n")
    @printf("Custo Total: USD %.2f/h | Tensão Barra 52: %.4f pu\n", custo_com_bess, v_b52_com_bess)
    @printf("Melhoria na Tensão da Barra 52: +%.4f pu\n", v_b52_com_bess - v_b52_sem_bess)
else
    println("A otimização com BESS não convergiu.")
end
println("="^70)
