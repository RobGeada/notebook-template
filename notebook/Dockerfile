FROM radanalyticsio/base-notebook

USER root

ENV NB_USER=nbuser
ENV NB_UID=1011

EXPOSE 8888

USER $NB_UID

ADD scripts /scripts
ADD start.sh /start.sh
ADD data /data

USER root

RUN chown -R $NB_USER:root /home/$NB_USER /data \
    && find /home/$NB_USER -type d -exec chmod g+rwx,o+rx {} \; \
    && find /home/$NB_USER -type f -exec chmod g+rw {} \; \
    && find /data -type d -exec chmod g+rwx,o+rx {} \; \
    && find /data -type f -exec chmod g+rw {} \; \
    && chmod -R -f g+rw /scripts

USER $NB_UID

ENV HOME /home/$NB_USER
ENV JUPYTER_NOTEBOOK_PASSWORD autodeploy

LABEL io.k8s.description="PySpark Jupyter Notebook." \
      io.k8s.display-name="PySpark Jupyter Notebook." \
      io.openshift.expose-services="8888:http"

CMD ["/start.sh"]
