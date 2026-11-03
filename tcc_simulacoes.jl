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

EXIT: Optimal Solution Found.
Cenário 5  | 1.10         | $ 9571.19          | 0.9564 pu
======================================================================


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
