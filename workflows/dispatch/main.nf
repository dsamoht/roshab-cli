#!/usr/bin/env nextflow

workflow DISPATCH {

    ch_input = Channel
        .from(file(params.input))
        .splitCsv(header: true)
        .map { row ->
                if (row.size() == 5) {
                    def sample_name = row.sample_name
                    def date = row.date
                    def info = row.info
                    def group = row.group
                    def reads = file(row.reads, checkIfExists: true)

                    return [ [  sample_name : sample_name, date: date, info: info, group: group ], reads ]
     
                } else {
                    exit 1, "Error in ${params.input}. Each row must contain 5 columns."
                }
        }

    emit:
    ch_input

}
