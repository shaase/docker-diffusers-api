ARG FROM_IMAGE="gadicc/diffusers-api-base:python3.9-pytorch1.12.1-cuda11.6-xformers"
# You only need the -banana variant if you need banana's optimization
# i.e. not relevant if you're using RUNTIME_DOWNLOADS
# BUMP: 3
# ARG FROM_IMAGE="gadicc/python3.9-pytorch1.12.1-cuda11.6-xformers-banana"
FROM ${FROM_IMAGE} as base
ENV FROM_IMAGE=${FROM_IMAGE}

# Note, docker uses HTTP_PROXY and HTTPS_PROXY (uppercase)
# We purposefully want those managed independently, as we want docker
# to manage its own cache.  This is just for pip, models, etc.
ARG http_proxy
ARG https_proxy
RUN if [ -n "$http_proxy" ] ; then \
  echo quit \
  | openssl s_client -proxy $(echo ${https_proxy} | cut -b 8-) -servername google.com -connect google.com:443 -showcerts \
  | sed 'H;1h;$!d;x; s/^.*\(-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\)\n---\nServer certificate.*$/\1/' \
  > /usr/local/share/ca-certificates/squid-self-signed.crt ; \
  update-ca-certificates ; \
  fi
ARG REQUESTS_CA_BUNDLE=${http_proxy:+/usr/local/share/ca-certificates/squid-self-signed.crt}

ARG DEBIAN_FRONTEND=noninteractive

FROM base AS patchmatch
ARG USE_PATCHMATCH=0
WORKDIR /tmp
COPY scripts/patchmatch-setup.sh .
RUN sh patchmatch-setup.sh

FROM base as output
RUN mkdir /api
WORKDIR /api

# we use latest pip in base image
# RUN pip3 install --upgrade pip

ADD requirements.txt requirements.txt
RUN pip install -r requirements.txt

# [39a3c77] fix: code snippet of instruct pix2pix from the docs. (#2446)
# Also includes misc LoRA fixes / improvements; xformers, enable/disable, etc.
RUN git clone https://github.com/huggingface/diffusers && cd diffusers && git checkout 39a3c77e0d4a22de189b02398cf2d003d299b4ae
WORKDIR /api
RUN pip install -e diffusers

# Deps for RUNNING (not building) earlier options
# ARG USE_PATCHMATCH=0
# RUN if [ "$USE_PATCHMATCH" = "1" ] ; then apt-get install -yqq python3-opencv ; fi
# COPY --from=patchmatch /tmp/PyPatchMatch PyPatchMatch

# TODO, just include by default, and handle all deps in OUR requirements.txt
# ARG USE_DREAMBOOTH=1
# ENV USE_DREAMBOOTH=${USE_DREAMBOOTH}

# RUN if [ "$USE_DREAMBOOTH" = "1" ] ; then \
#     # By specifying the same torch version as conda, it won't download again.
#     # Without this, it will upgrade torch, break xformers, make bigger image.
#     pip install -r diffusers/examples/dreambooth/requirements.txt bitsandbytes torch==1.12.1 ; \
#   fi
# RUN if [ "$USE_DREAMBOOTH" = "1" ] ; then apt-get install git-lfs ; fi

COPY api/ .
EXPOSE 8000

# Model id, precision, etc.
ARG MODEL_ID="stabilityai/stable-diffusion-2-1-base"
ENV MODEL_ID=${MODEL_ID}
# ARG HF_MODEL_ID=""
# ENV HF_MODEL_ID=${HF_MODEL_ID}
ARG MODEL_PRECISION="fp16"
ENV MODEL_PRECISION=${MODEL_PRECISION}
ARG MODEL_REVISION="fp16"
ENV MODEL_REVISION=${MODEL_REVISION}
#ARG MODEL_URL="s3://"
ARG MODEL_URL=""
ENV MODEL_URL=${MODEL_URL}

# To use a .ckpt file, put the details here.
ARG CHECKPOINT_FILE_NAME
ENV CHECKPOINT_FILE_NAME=${CHECKPOINT_FILE_NAME}
ENV CHECKPOINT_URL="s3:///rad-science-ai-checkpoints/public/${CHECKPOINT_FILE_NAME}"
ARG CHECKPOINT_CONFIG_URL=""
ENV CHECKPOINT_CONFIG_URL=${CHECKPOINT_CONFIG_URL}

ARG PIPELINE="ALL"
ENV PIPELINE=${PIPELINE}


# AWS / S3-compatible storage (see docs)
ARG AWS_ACCESS_KEY_ID="AKIAUWCA4RC6GGVTU2WO"
ARG AWS_SECRET_ACCESS_KEY
# AWS, use "us-west-1" for banana; leave blank for Cloudflare R2.
ARG AWS_DEFAULT_REGION="us-east-2"
ARG AWS_S3_DEFAULT_BUCKET
# Only if your non-AWS S3-compatible provider told you exactly what
# to put here (e.g. for Cloudflare R2, etc.)
ARG AWS_S3_ENDPOINT_URL

ENV AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
ENV AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
ENV AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
ENV AWS_S3_DEFAULT_BUCKET=${AWS_S3_DEFAULT_BUCKET}
ENV AWS_S3_ENDPOINT_URL=${AWS_S3_ENDPOINT_URL}

# Download the model
ENV RUNTIME_DOWNLOADS=0
RUN echo "Going to download $CHECKPOINT_URL"
RUN python3 download.py
# RUN python3 download_checkpoint.py
# RUN python3 convert_to_diffusers.py

# Send (optionally signed) status updates to a REST endpoint
ARG SEND_URL
ENV SEND_URL=${SEND_URL}
ARG SIGN_KEY
ENV SIGN_KEY=${SIGN_KEY}


ARG SAFETENSORS_FAST_GPU=1
ENV SAFETENSORS_FAST_GPU=${SAFETENSORS_FAST_GPU}

CMD python3 -u server.py

