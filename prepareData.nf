#!/usr/bin/env nextflow

def checkGenome() {
    if(params.genome == null) {
        exit 1, "Please provide a FASTA sequence of the reference genome."
    } else{
        genome = file(params.genome, type: 'file')  // The whole genome sequence.
    }
    return genome
}

def checkGenes() {    
    if(params.genes == null) {
        exit 1, "Please provide an annotation GTF file."
    } else{
        genes = file(params.genes, type: 'file')  // The genome annotation file.
    }
    return genes
}

def checkKrakenDir() {
    if(params.kraken_dir == null) {
        exit 1, "Please provide a path to save the Kraken database"
    } else{
        out_path = file(params.kraken_dir, type: 'file') 
    }
    return out_path
}


switch (params.mode) {
    case ['getContainers']:
        link_base = "shub://phelelani/nf-rnaSeqCount:"
        shub_images = Channel.from( ["${link_base}star", "${link_base}htseqcount", "${link_base}featurecounts", "${link_base}multiqc", "${link_base}trinity"] )
        
        process downloadContainers_process {
            cpus 1
            memory '2 GB'
            time '2h'
            scratch '$HOME/tmp'
            tag { "Downloading: $link" }
            publishDir "$baseDir/containers", mode: 'copy', overwrite: true, pattern: "*.simg"
            
            input:
            each link from shub_images
            
            output:
            file("*.simg") into containers
        
            """
            singularity pull ${link}
            """
        }

        containers.subscribe { println it }

        break
    case ['generateStarIndex']:
        
        checkGenome()
        checkGenes()
        out_path = genome.getParent()
        
        process generateSTARIndex {
            cpus 13
            memory '100 GB'
            time '20h'
            scratch '$HOME/tmp'
            tag { "Generate Star Index" }
            publishDir "$out_path", mode: 'copy', overwrite: true
            
            output:
                file("*") into star_index
            
            """
            STAR --runThreadN 12 \
                --runMode genomeGenerate \
                --genomeDir . \
                --genomeFastaFiles ${genome} \
                --sjdbGTFfile ${genes} \
                --sjdbOverhang 99
            """
        }
    
        star_index.subscribe { println it }
        break

    case ['generateBowtieIndex']:
        
        checkGenome()
        out_path = genome.getParent()
        
        process generateBowtie2Index {
            cpus 13
            memory '100 GB'
            time '20h'
            scratch '$HOME/tmp'
            tag { "Generate Bowtie2 Index" }
            publishDir "$out_path", mode: 'copy', overwrite: false
        
            output:
            file("*") into bowtie_index
            
            """
            bowtie2-build --threads 12 ${genome} genome
            """
        }   
    
        bowtie_index.subscribe { println it }
        break

    case ['generateKrakenDB']:
        
        checkKrakenDir()
        
        process generateKrakenDB {
            cpus 7
            memory '200 GB'
            time '30h'
            scratch '$HOME/tmp'
            tag { "Generate Kraken DB" }
            publishDir "$out_path", mode: 'copy', overwrite: true
            
            output:
            file("*") into kraken_db
        
            """
            kraken-build --standard --threads 6 --db kraken_std
            """
        }   

        kraken_db.subscribe { println it }
        break
}
