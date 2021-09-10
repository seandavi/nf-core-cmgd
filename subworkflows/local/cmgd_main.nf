include { FASTERQDUMP } from '../../modules/local/fasterqdump.nf'

//process fasterq_dump {
//    publishDir "${params.publish_dir}/${workflow.sessionId}/fasterq_dump", pattern: "{fastq_line_count.txt,*_fastqc/fastqc_data.txt,sampleinfo.txt,.command*}"
//    
//    maxForks 80
//    cpus 4
//    memory "16g"
//    errorStrategy  { task.attempt <= maxRetries  ? 'retry' : 'finish' }
//    maxRetries 4
//
//    tag "${srr}"
//
//    input:
//    val srr
//
//    output:
//    val(srr)
//    path "out.fastq.gz", emit: fastq
//    path "*_fastqc/fastqc_data.txt", emit: fastqc_data
//    path "fastq_line_count.txt"
//    path ".command*"
//    path "sampleinfo.txt"
//
//    script:
//      """
//      echo "accessions: ${srr}" > sampleinfo.txt
//      fasterq-dump \
//          --skip-technical \
//          --force \
//          --threads ${task.cpus} \
//          --split-files ${srr.join(" ")}
//      cat *.fastq | gzip > out.fastq.gz
//      gunzip -c out.fastq.gz | wc -l > fastq_line_count.txt
//      rm *.fastq
//      seqtk sample -s100 out.fastq.gz 50000 > out_sample.fastq
//      fastqc --extract out_sample.fastq
//      rm out_sample.fastq
//      """
//}



process install_metaphlan_db {
    cpus 8
    memory '32g'

    storeDir "${params.store_dir}"

    output:
    path 'metaphlan', emit: metaphlan_db, type: 'dir'
    path ".command*"

    script:
      """
      metaphlan --install --index latest --bowtie2db metaphlan
      """
}

process metaphlan_bugs_list {
    publishDir "${params.publish_dir}/${workflow.sessionId}/metaphlan_bugs_list", pattern: "{*tsv.gz,.command*}"
    errorStrategy 'ignore'
    
    // tag "${rowhash}"

    time "1d"
    cpus 16
    memory { 32.GB * task.attempt }
    
    input:
    path fastq
    path metaphlan_db


    output:
    path 'bowtie2.out.gz', emit: metaphlan_bt2
    path 'metaphlan_bugs_list.tsv', emit: metaphlan_bugs_list
    path 'metaphlan_bugs_list.tsv.gz', emit: metaphlan_bugs_list_gz
    path ".command*"

    script:
    """
    find .
    metaphlan --input_type fastq \
        --index ${params.metaphlan_index} \
        --bowtie2db metaphlan \
        --samout sam.bz2 \
        --bowtie2out bowtie2.out \
        --nproc ${task.cpus} \
        -o metaphlan_bugs_list.tsv \
        ${fastq}

    gzip -c metaphlan_bugs_list.tsv > metaphlan_bugs_list.tsv.gz
    gzip bowtie2.out
    """
}

process metaphlan_markers {
    publishDir "${params.publish_dir}/${workflow.sessionId}/metaphlan_markers"
    
    cpus 4
    memory "16g"

    input:
    path metaphlan_bt2
    path metaphlan_db

    output:
    path "marker_abundance.tsv.gz", emit: marker_abundance
    path "marker_presence.tsv.gz", emit: marker_presence
    path ".command*"

    script:
    """
    metaphlan --input_type bowtie2out \
        --index ${params.metaphlan_index} \
        --bowtie2db metaphlan \
        -t marker_pres_table \
        -o marker_presence.tsv \
        <( gunzip -c ${metaphlan_bt2} )    
    metaphlan --input_type bowtie2out \
        --index ${params.metaphlan_index} \
        --bowtie2db metaphlan \
        -t marker_ab_table \
        -o marker_abundance.tsv \
        <( gunzip -c ${metaphlan_bt2} )
    gzip *.tsv
    """
}


process chocophlan_db {
    cpus 1
    memory "1g"
    time "1d"

    storeDir "${params.store_dir}"

    output:
    path "chocophlan", emit: chocophlan_db, type: 'dir'
    path ".command*"

    script:
    """
    humann_databases --update-config no --download chocophlan ${params.chocophlan} .
    """
}


process uniref_db {
    cpus 1
    memory "1g"
    time "1d"

    storeDir "${params.store_dir}"

    output:
    path "uniref", emit: uniref_db, type: 'dir'
    path ".command*"

    script:
    """
    humann_databases --update-config no --download uniref ${params.uniref} .
    """
}


process humann {
    publishDir "${params.publish_dir}/${workflow.sessionId}/humann"
    cpus 16

    errorStrategy 'ignore'

    time "3d"
    memory "64g"

    input:
    path fastq
    path metaphlan_bugs_list // metaphlan_bugs_list.tsv
    path chocophlan_db
    path uniref_db

    output:
    // lots of files....
    path("out_genefamilies.tsv.gz")
    path("out_genefamilies_cpm.tsv.gz")
    path("out_genefamilies_relab.tsv.gz")
    path("out_genefamilies_stratified.tsv.gz")
    path("out_genefamilies_unstratified.tsv.gz")
    path("out_genefamilies_cpm_stratified.tsv.gz")
    path("out_genefamilies_relab_stratified.tsv.gz")
    path("out_genefamilies_cpm_unstratified.tsv.gz")
    path("out_genefamilies_relab_unstratified.tsv.gz")
    path("out_pathabundance.tsv.gz")
    path("out_pathabundance_cpm.tsv.gz")
    path("out_pathabundance_relab.tsv.gz")
    path("out_pathabundance_stratified.tsv.gz")
    path("out_pathabundance_unstratified.tsv.gz")
    path("out_pathabundance_cpm_stratified.tsv.gz")
    path("out_pathabundance_relab_stratified.tsv.gz")
    path("out_pathabundance_cpm_unstratified.tsv.gz")
    path("out_pathabundance_relab_unstratified.tsv.gz")
    path("out_pathcoverage_unstratified.tsv.gz")
    path("out_pathcoverage_stratified.tsv.gz")
    path("out_pathcoverage.tsv.gz")
    path ".command*"

    script:
    """
    humann -i ${fastq} \
        -o '.' \
        --verbose \
        --metaphlan-options "-t rel_ab --index latest" \
        --nucleotide-database ${chocophlan_db} \
        --taxonomic-profile ${metaphlan_bugs_list} \
        --protein-database ${uniref_db} \
        --threads ${task.cpus}

    humann_renorm_table \
        --input out_pathabundance.tsv \
        --output out_pathabundance_cpm.tsv \
        --units cpm

    humann_renorm_table \
        --input out_genefamilies.tsv \
        --output out_genefamilies_cpm.tsv \
        --units cpm

    humann_renorm_table \
        --input out_genefamilies.tsv \
        --output out_genefamilies_relab.tsv \
        --units relab

    humann_renorm_table \
        --input out_pathabundance.tsv \
        --output out_pathabundance_relab.tsv \
        --units relab

    humann_split_stratified_table -i out_pathabundance.tsv -o .
    humann_split_stratified_table -i out_pathabundance_cpm.tsv -o .
    humann_split_stratified_table -i out_pathabundance_relab.tsv -o .
    humann_split_stratified_table -i out_pathcoverage.tsv -o .
    humann_split_stratified_table -i out_genefamilies.tsv -o .
    humann_split_stratified_table -i out_genefamilies_cpm.tsv -o .
    humann_split_stratified_table -i out_genefamilies_relab.tsv -o .
    gzip out_*tsv
    """
}

def generate_row_tuple(row) {
    accessions=row.NCBI_accession.split(';');
    uuid = row.uuid;
    // Create a hash of sampleID and joined accessions for
    // use as a unique id.
    // rowhash = "${accessions.sort().join(' ')}".md5().toString()
    return tuple(accessions, uuid)
}

workflow CMGD_MAIN {
    // Channel.from(samp).combine(Channel.from(runs)) | fasterq_dump | groupTuple | map { it -> [ it[0], it[1].flatten ] } | view
    // samples = Channel.fromPath(params.metadata_tsv)
    //    .splitCsv(header: true, quote: '"') 
    //   .map { row -> generate_row_tuple(row) }    
    // samples = items
    // amples = params.srr.split(';')
    take:
    srr

    main:
    def meta = [id:'abc']
    FASTERQDUMP(meta,srr.split(';'))

    install_metaphlan_db()
    uniref_db()
    chocophlan_db()
    
    metaphlan_bugs_list(
        FASTERQDUMP.out.fastq,
        install_metaphlan_db.out.metaphlan_db.collect())
    metaphlan_markers(
        metaphlan_bugs_list.out.metaphlan_bt2,
        install_metaphlan_db.out.metaphlan_db.collect())
    humann(
        FASTERQDUMP.out.fastq,
        metaphlan_bugs_list.out.metaphlan_bugs_list,
        chocophlan_db.out.chocophlan_db,
        uniref_db.out.uniref_db)
}

