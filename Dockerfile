# Base image (linux/amd64 for Apple Silicon and for SciLifeLab Serve)
FROM rocker/shiny:4.4.1

# General updates + Python for SigProfilerAssignment
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y git libxml2-dev libmagick++-dev libssl-dev libharfbuzz-dev libfribidi-dev python3 python3-pip curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


RUN Rscript -e 'install.packages(c("shiny", "bslib", "ggplot2", "dplyr", "tidyr", "readr", "markdown", "paletteer", "scales", "tibble"), dependencies = TRUE)'

# Install reference genomes in builder only (tar files stay in this stage, discarded in final image)
COPY genome/ /tmp/genome/
RUN python3 -m pip install SigProfilerMatrixGenerator==1.3.6 SigProfilerAssignment==1.1.3 pandas && \
    python3 -c "import SigProfilerMatrixGenerator.install as genInstall; genInstall.install('GRCh37', offline_files_path='/tmp/genome'); genInstall.install('GRCh38', offline_files_path='/tmp/genome')" && \
    python3 -c "from SigProfilerMatrixGenerator.scripts.ref_install import reference_dir; d=reference_dir(); t=d.get_tsb_dir(); import os; assert os.path.isdir(t/'GRCh37') and os.path.isdir(t/'GRCh38'), 'Reference genomes missing'" && \
    rm -rf /tmp/genome 


# Copy app files without genome/ so final image has no tar files
RUN rm -rf /srv/shiny-server/*
COPY /app/ /srv/shiny-server/


# Ensure shiny user exists with UID 999 (only create if missing; base image may already have it)
RUN if id shiny &>/dev/null && [ "$(id -u shiny)" -ne 999 ]; then \
        userdel -r shiny 2>/dev/null || true; \
        id -u 999 &>/dev/null && userdel -r "$(id -un 999)" 2>/dev/null || true; \
    fi; \
    (id -u shiny &>/dev/null && [ "$(id -u shiny)" -eq 999 ]) || useradd -u 999 -m -s /bin/bash shiny; \
    chown -R shiny:shiny /srv/shiny-server/ /var/lib/shiny-server/ /var/log/shiny-server/

# Other settings
USER shiny
EXPOSE 3838

CMD ["/usr/bin/shiny-server"]
