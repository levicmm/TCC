# Simulação de Integração de Data Centers de IA em Redes de Transmissão (TCC)

Repositório oficial do Trabalho de Conclusão de Curso (TCC) em Engenharia Elétrica na Universidade Federal do Ceará (UFC). 

O projeto utiliza **Julia** (PowerModels e Ipopt) para avaliar o impacto técnico e econômico da inserção de Data Centers de Inteligência Artificial em redes de transmissão de grande porte (sistemas IEEE 14 e IEEE 118 barras).

## Estrutura do Projeto:
- **Etapa 1 & 2:** Simulação do Caso Base e inserção estática de carga (considerando fator PUE).
- **Etapa 3:** Análise estocástica mapeando janelas de variação de carga de treinamento de IA.
- **Etapa 4:** Varredura nodal (*Node Scanning*) para identificação do nó crítico (Barra 52 no sistema IEEE 118).
- **Etapa 5:** Mitigação de afundamentos de tensão via *Peak Shaving* com Sistemas de Armazenamento de Energia (BESS).
