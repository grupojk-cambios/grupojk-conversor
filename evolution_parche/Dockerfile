# Evolution API 2.3.7 con el parche que evita que la instancia quede "conectada" pero sorda.
#
# Se parte de la imagen oficial y SOLO se le aplica el parche. No se cambia el ENTRYPOINT
# (que es:  /bin/bash -c ". ./Docker/scripts/deploy_database.sh && npm run start:prod"),
# asi que Evolution arranca exactamente igual que antes.
#
# El --estricto hace que la CONSTRUCCION falle si el parche no se pudo aplicar. Es a
# proposito: es mejor que falle aqui y nos enteremos, que terminar con una imagen que
# parece arreglada y no lo esta.
#
# El contexto de construccion debe ser la raiz del repositorio.

FROM evoapicloud/evolution-api:v2.3.7

COPY scripts/parche_status_evolution.cjs /parche_status_evolution.cjs
RUN node /parche_status_evolution.cjs --estricto
