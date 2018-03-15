#!/usr/bin/env nextflow

params.data = "/spaces/phelelani/ssc_data/data_trimmed/inflated" 
params.out = "/spaces/phelelani/ssc_data/nf-rnaSeqCount"
params.genes = "/global/blast/reference_genomes/Homo_sapiens/Ensembl/GRCh38/Annotation/Genes/genes.gtf"
params.refSeq = "/global/blast/reference_genomes/Homo_sapiens/Ensembl/GRCh38/Sequence/WholeGenomeFasta/genome.fa"
params.genome = "/global/blast/reference_genomes/Homo_sapiens/Ensembl/GRCh38/Sequence/STARIndex"

data_path = params.data
out_path = file(params.out)
genes = params.genes
genome = params.genome
refSeq = params.refSeq

out_path.mkdir()

read_pair = Channel.fromFilePairs("${data_path}/*R[1,2].fastq", type: 'file')

// 1. Align reads to reference genome
process runSTAR_process {
    cpus 6
    memory '40 GB'
    time '10h'
    scratch '$HOME/tmp'
    tag { sample }
    publishDir "$out_path/${sample}", mode: 'copy', overwrite: false

    input:
    set sample, file(reads) from read_pair

    output:
    set sample, "${sample}*" into star_results
    set sample, file("${sample}_Aligned.sortedByCoord.out.bam") into bams_htseqCounts, bams_featureCounts
    
    """
    /bin/hostname
    STAR --runMode alignReads \
        --genomeDir $genome \
        --readFilesIn ${reads.get(0)} ${reads.get(1)} \
        --runThreadN 5 \
        --outSAMtype BAM SortedByCoordinate \
        --outFileNamePrefix ${sample}_
    """
}

// 2. Get raw counts using HTSeq-count
process runHTSeqCount_process {
    cpus 4
    memory '5 GB'
    time '10h'
    scratch '$HOME/tmp'
    tag { sample }
    publishDir "$out_path/htseqCounts", mode: 'copy', overwrite: false

    input:
    set sample, file(bam) from bams_htseqCounts

    output:
    set sample, "${sample}.txt" into htseqCounts
    
    """
    /bin/hostname
    htseq-count -f bam \
        -r pos \
        -i gene_id \
        -a 10 \
        -s reverse \
        -m union \
        -t exon \
        $bam $genes > ${sample}.txt
    """
}

// 3a. Get all the bam file locations to process with featureCounts
bams_featureCounts
.collectFile () { item -> [ 'sample_bams.txt', "${item.get(1)}" + ' ' ] }
.set { sample_bams }

// 3. Get raw counts using featureCounts
process runFeatureCounts_process {
    cpus 6
    memory '5 GB'
    time '10h'
    scratch '$HOME/tmp'
    tag { sample }
    publishDir "$out_path/featureCounts", mode: 'copy', overwrite: false

    input:
    file(samples) from sample_bams

    output:
    file('gene_counts*') into featureCounts
    
    """
    /bin/hostname
    featureCounts -p -B -C -P -J -s 2 \
        -G $refSeq -J \
        -t exon \
        -d 40 \
        -g gene_id \
        -a $genes \
        -T 5 \
        -o gene_counts.txt \
        `< ${samples}`
    """
}

// 4a. Collect files for STAR QC
star_results.collectFile () { item -> [ 'qc_star.txt', "${item.get(1).find { it =~ 'Log.final.out' } }" + ' ' ] }
.set { qc_star }

// 4b. Collect files for HTSeq QC
htseqCounts
.collectFile () { item -> [ 'qc_htseqcounts.txt', "${item.get(1)}" + ' ' ] }
.set { qc_htseqcounts }

// 4c. Collect files for featureCounts QC
featureCounts
.collectFile () { item -> [ 'qc_featurecounts.txt', "${item.find { it =~ 'txt.summary' } }" + ' ' ] }
.set { qc_featurecounts }

// 4. Get QC for STAR, HTSeqCounts and featureCounts
process runMultiQC_process {
    cpus 1
    memory '5 GB'
    time '10h'
    scratch '$HOME/tmp'
    tag { sample }
    publishDir "$out_path/report_QC", mode: 'copy', overwrite: false

    input:
    file(star) from qc_star
    file(htseqcounts) from qc_htseqcounts
    file(featurecounts) from qc_featurecounts

    output:
    file('*') into multiQC
    
    """
    /bin/hostname
    multiqc `< ${star}` `< ${htseqcounts}` `< ${featurecounts}` --force
    """
}


workflow.onComplete {
    println "----------------------------"
    println "Pipeline execution summary:"
    println "----------------------------"
    println "Execution command   : ${workflow.commandLine}"
    println "Execution name      : ${workflow.runName}"
    println "Workflow start      : ${workflow.start}"
    println "Workflow end        : ${workflow.complete}"
    println "Workflow duration   : ${workflow.duration}"
    println "Workflow completed? : ${workflow.success}"
    println "Work directory      : ${workflow.workDir}"
    println "Project directory   : ${workflow.projectDir}"
    println "Execution directory : ${workflow.launchDir}"
    println "Configuration files : ${workflow.configFiles}"
    println "Workflow containers : ${workflow.container}"
    println "exit status : ${workflow.exitStatus}"
    println "Error report: ${workflow.errorReport ?: '-'}"
    println "---------------------------"
}

workflow.onError {
    println "Oohhh DANG IT!!... Pipeline execution stopped with the following message: ${workflow.errorMessage}"
}
