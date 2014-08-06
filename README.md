ncbi-test
=========

This repository contains a set of scripts to download 11TB of SRA data files from NCBI.

Using the `pcurl.py` script
===========================
The `pcurl.py` script accepts the following flags:
*  `-i <filename>`  -- the list of files (located at NCBI) to fetch.  Default: `stdin`
*  `-o <directory>` -- the destination direcotry.  Default: `.`
*  `-j <jobs>` -- the number of jobs, or instances of `curl`, to run.  Default: 1
*  `-p` -- show more progress as the script runs (every two seconds)

__Example__:

     pcurl.py -i sralist/sralist00 -o /raid/output -j 8
     
     
Using the `parascp.sh` script
=============================
The `parascp.sh` is invoked the following way:

    PARASCP_CORES=5 ascppar.sh -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh \
        -G 8M -T -Ql 5g -Z 8232 -- -L/tmp --mode recv --host 130.14.250.13 --user anonftp \
        --file-list sralist/sralist01 /raid/output

See the `README.parascp` file more details of the script flags and options.  The `PARASCP_CORES` variable defines the number of `ascp` instances to invoke.  The `-G` flag sets the write size, and should be set to what works best for your system.  The MTU size of 8232 is recommended by Aspera for interacting with NCBI.  The host IP address we used was consistently faster than other servers hosted by NCBI.  The argument to the `--file-list` flag is the list of the files to fetch from NCBI.  The final argument is the destination directory.

Using the `fetchall.sh` script
==============================t
