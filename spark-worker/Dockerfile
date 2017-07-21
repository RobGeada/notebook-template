FROM radanalyticsio/openshift-spark

USER root

RUN yum install -y centos-release-scl epel-release gcc \
    && yum-config-manager --enable rhel-server-rhscl-7-rpms \
    && yum install -y python27 && yum clean all -y

RUN mkdir -p /data
COPY data /data
RUN chmod -R 1777 /data

USER 185

CMD ["scl", "enable", "python27", "/opt/spark/bin/launch.sh"]