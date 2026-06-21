#!/usr/bin/env nextflow

workflow DISPATCH {

    emit:
    channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->

            def expectedKeys = ['sample_id', 'date', 'info', 'group', 'reads']


            if (!row.keySet().containsAll(expectedKeys)) {
                error "Error in ${params.input}: missing or incorrect columns. Expected: ${expectedKeys}. Found: ${row.keySet()}"
            }

            if (row.values().any { it == null || it.toString().trim() == '' }) {
                error "Error in ${params.input}: Row contains missing values -> ${row}"
            }

            def sample_id = row.sample_id
            def date      = row.date
            def info      = row.info
            def group     = row.group
            def reads     = file(row.reads, checkIfExists: true)
            
            return [ [ sample_id: sample_id, date: date, info: info, group: group ], reads ]
        }
}
