#!/bin/bash
# Autor: Isadora Figueiredo
# Descrição: realiza o backup dos bancos PostgreSQL 
# Última Atualização: 09/10/2020

#-------------------------------[ Declaração de Variáveis Globais ]------------------------------------

HOJE=$(date +%Y%m%d)
HORA=$(date +%H%M%S)
BACKUP_DIR="/diretorio_de_armazenamento_dos_backups"
LOG="${BACKUP_DIR}/arquivo.log"
WEBHOOK="https://url-do-webhook.com.br"

#--------------------------------[ Variáveis de Conexão PostgreSQL ]-----------------------------------

BIN_PGSQL="/path_do_bin_do_postgres"
SERVIDOR="ip_ou_nome_do_servidor_de_banco"
PORTA="5432"
USUARIO="postgres"
RETENCAO="7"
EXCLUDE_LIST=("'postgres', 'db_para_nao_fazer_backup'")

#--------------------------------[ Declaração das Funções ]--------------------------------------------

function backupBancos {
	RETURN="-1"
    if [ -d "${BACKUP_DIR}" ]; then
        # Lista todos os bancos que não sejam templates e que não estão na lista de exclusão (EXCLUDE_LIST).
        ${BIN_PGSQL}/psql --user ${USUARIO} --host ${SERVIDOR} --port ${PORTA} -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname not in (${EXCLUDE_LIST});" | while read DB
            do
                if [ ! -z ${DB} ]; then
                    CAMINHO="${BACKUP_DIR}/${DB}_backup_${HOJE}_${HORA}.gz"
                    echo "$(date +%d/%m%Y) - $(date +%T) - Executando backup do banco ${DB} ..." | tee --append "${LOG}"
                    
                   ${BIN_PGSQL}/pg_dump --verbose --user ${USUARIO} --host ${SERVIDOR} --port ${PORTA} --format custom ${DB} | gzip > ${CAMINHO}
                     
                    RETURN=$?
                    echo "$(date +%d/%m%Y) - $(date +%T) - Feito!" | tee --append "${LOG}"
                    sleep 2
            
                    status ${RETURN} ${DB} ${CAMINHO}
                fi
            done
    else
        echo "$(date +%d/%m%Y) - $(date +%T) - Erro de execução: o diretório ${BACKUP_DIR} não está disponível." | tee --append "${LOG}"
        echo | tee --append "${LOG}"
    fi

    # Chama a função retencaoBackups
    retencaoBackups
}

function retencaoBackups {
    seleciona_bancos=$(find "${BACKUP_DIR}" -maxdepth 1 -ctime +"${RETENCAO}" -type f -name "*.gz")

    if [ -n "$seleciona_bancos" ]; then 
        echo "$(date +%d/%m%Y) - $(date +%T) - Os arquivos abaixo serão excluídos conforme a política de ${RETENCAO} dias de retenção." | tee --append "${LOG}"
        echo | tee --append "${LOG}"
        echo "$seleciona_bancos" | tee --append "${LOG}"
        echo | tee --append "${LOG}"

        find "${BACKUP_DIR}" -maxdepth 1 -ctime +"${RETENCAO}" -type f -name "*.gz" -delete
    else
        echo "$(date +%d/%m%Y) - $(date +%T) - Nenhum arquivo a ser excluído conforme a política de ${RETENCAO} dias de retenção." | tee --append "${LOG}"
        echo | tee --append "${LOG}"
    fi
}

function status {
  RETURN=$1
  BD_NAME=$2
  ARQUIVO=$3

  #Mostrar apenas o nome do arquivo gerado
  NOME_BKP=$(ls -lh ${ARQUIVO} | awk '{ print $9 };' | rev |  sed -e 's/\/.*\///g'| rev)

  #Mostrar apenas o tamanho do arquivo gerado
  TAMANHO_BKP=$(ls -lh ${ARQUIVO} | awk '{ print $5 };')

  if [ $RETURN -eq 0 ]; then
    EMOJI=white_check_mark
    echo -e "\033[32m-- $(date +%T) - O backup do banco de dados ${BD_NAME} foi realizado com sucesso. --\033[m" | tee --append ${LOG}
    chatnotification "O backup do banco de dados *${BD_NAME}* no servidor *${SERVIDOR}* foi realizado. Arquivo *${NOME_BKP}* tamanho: *${TAMANHO_BKP}*" ${EMOJI}
  else
    EMOJI=negative_squared_cross_mark
    echo -e "\033[31m-- $(date +%T) - Ocorreu uma falha durante o backup do banco de dados ${BD_NAME}. --\033[m" | tee --append ${LOG}
    chatnotification "Ocorreu uma falha durante o backup do banco de dados *${BD_NAME}* no servidor *${SERVIDOR}*." ${EMOJI}
  fi
}

function chatnotification {
  curl -X POST -H 'Content-Type: application/json'  --data "{\"username\":\"Agente de Backups\",\"emoji\":\":${EMOJI}:\",\"text\":\"${1}\"}" ${WEBHOOK}
  echo -e "-- Enviando mensagem do status do backup. --\n" | tee --append ${LOG}
}

#--------------------------------[ Início da Execução do Script ]------------------------------------
echo "$(date +%d/%m%Y) - $(date +%T) - Início da tarefa de backup" | tee --append "${LOG}"
echo | tee --append "${LOG}"

# Testa a conexão com o servidor
testa_conexao=$(curl --connect-timeout 2 ${SERVIDOR}:${PORTA} 2>&1 | grep "Empty reply from server")

if [ -n "$testa_conexao" ]; then
    echo | tee --append "${LOG}"
    echo "$(date +%d/%m%Y) - $(date +%T) - Conexão estabelecida com o ${SERVIDOR}" | tee --append "${LOG}"
    echo | tee --append "${LOG}"

      #Chama a função backupBancos
      backupBancos
else
    EMOJI=negative_squared_cross_mark
    echo "$(date +%d/%m%Y) - $(date +%T) - Erro de execução: falha de conexão com o ${SERVIDOR}" | tee --append "${LOG}"
    echo | tee --append "${LOG}"
    chatnotification "Ocorreu erro de execução: falha de conexão com o *${SERVIDOR}*." ${EMOJI}
fi

echo "$(date +%d/%m%Y) - $(date +%T) - Fim da tarefa de backup." | tee --append "${LOG}"
echo "---------------------------------------------------------" | tee --append "${LOG}"