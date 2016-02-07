# ASRdys

### Description
ASRdys is a Kaldi recipe to build an ASR for speakers with dysarthria. The recipe works on the Torgo database [1] so you need to obtain this data first and include its location into the path.sh file.
Several models are used in the pipeline implemented in run.sh.

### Usage

To train several models on all the speakers except one for testing do:
```sh
  bash ./run.sh <test_speaker>
```
where <test_speaker> is one of the 15 speakers in the database.

To train several models on 15 different configurations taking a different test speaker at a time do:
```sh
  bash ./runAllTests.sh
```
Remember to adapt path.sh to your necessities.

#### TODO
Update the Deep Learning scripts  
Add a RESULTS file

### Authors
Cristina España-Bonet  
(especific scripts only for the Torgo database: ./local)

### References
[1] Frank Rudzicz , Aravind Kumar Namasivayam and Talya Wolff.
*The TORGO database of acoustic and articulatory speech from speakers with dysarthria*. 
Language Resources and Evaluation, December 2012, Volume 46, Issue 4, pp 523-541 

