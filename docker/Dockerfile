FROM swift:5.1.3 as builder

RUN apt-get -qq update && apt-get install -y \
  zlib1g-dev \
  && rm -r /var/lib/apt/lists/*
