# --------------------------------------------------------------------
# Copyright (c) 2024, WSO2 Inc. (http://wso2.com) 
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# -----------------------------------------------------------------------

FROM choreowbcuserappsescargot.azurecr.io/ballerina-central/v2/base:latest AS ballerina-tools-build
LABEL maintainer "ballerina.io"

USER root

COPY . /home/work-dir/solr_client
WORKDIR /home/work-dir/solr_client

RUN bal build

FROM eclipse-temurin:17-jre-alpine

RUN mkdir -p /work-dir \
    && addgroup troupe \
    && adduser -S -s /bin/bash -g 'ballerina' -G troupe -D ballerina \
    && apk upgrade \
    && apk add --no-cache libc6-compat\
    && rm -rf /var/cache/apk/* \
    && chown -R ballerina:troupe /work-dir \
    && chown -R ballerina:troupe /mnt

USER ballerina

WORKDIR /home/work-dir/

COPY --from=ballerina-tools-build /home/work-dir/solr_client/target/bin/solr_client.jar /home/work-dir/
COPY --from=ballerina-tools-build /home/work-dir/solr_client/resources /home/work-dir/resources

EXPOSE 8080

ENV JAVA_TOOL_OPTIONS "-XX:+UseContainerSupport -XX:MaxRAMPercentage=80.0 -XX:TieredStopAtLevel=1"
USER 10500
CMD [ "java", "-jar", "solr_client.jar" ]
    