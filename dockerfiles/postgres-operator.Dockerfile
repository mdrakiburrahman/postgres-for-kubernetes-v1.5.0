CMD ["bash"]
RUN RUN groupadd -g 1000 NONROOT # buildkit
RUN RUN useradd -M -g 1000 -u 1000 -c "nonroot user" NONROOT # buildkit
RUN RUN mkdir /home/nonroot  \
        && chown NONROOT /home/nonroot # buildkit
USER 1000:1000
WORKDIR /
COPY /workspace/manager . # buildkit
        manager

ARG DATE=unknown
LABEL name=postgres-operator vendor=VMware, Inc build_date=2022-01-04T21:25:32
ENTRYPOINT ["/manager"]