-- Tabel kategori pelapor
CREATE TABLE IF NOT EXISTS kategori_pelapor (
    id_kategori_pelapor SERIAL PRIMARY KEY,
    kategori VARCHAR(50) NOT NULL UNIQUE,
    deskripsi TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Tabel status terlapor
CREATE TABLE IF NOT EXISTS status (
    id_status SERIAL PRIMARY KEY,
    status VARCHAR(100) NOT NULL UNIQUE,
    deskripsi TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Tabel utama laporan kasus
CREATE TABLE IF NOT EXISTS laporan_kasus (
    id_laporan SERIAL PRIMARY KEY,
    nomor_referensi VARCHAR(20) UNIQUE NOT NULL,
    tanggal_laporan TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    kategori_pelapor_id INTEGER REFERENCES kategori_pelapor(id_kategori_pelapor),
    nama_pelapor VARCHAR(200) NOT NULL,
    program_studi VARCHAR(200),
    kelas VARCHAR(50),
    jenis_kelamin VARCHAR(50),
    nomor_telepon VARCHAR(50),
    alamat VARCHAR(200),
    email VARCHAR(200),
    is_disabilitas BOOLEAN DEFAULT FALSE,
    jenis_disabilitas VARCHAR(200),
    jenis_kekerasan VARCHAR(200),
    deskripsi_kejadian TEXT NOT NULL,
    status_terlapor_id INTEGER REFERENCES status(id_status),
    alasan_lapor TEXT,
    kontak_lain VARCHAR(200),
    status_laporan VARCHAR(50) DEFAULT 'Submitted',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Tabel Kategori Materi
CREATE TABLE IF NOT EXISTS kategori_materi (
    id_kategori_materi SERIAL PRIMARY KEY,
    kategori VARCHAR(100) NOT NULL UNIQUE,
    deskripsi TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Tabel Materi
CREATE TABLE IF NOT EXISTS materi (
    id_materi SERIAL PRIMARY KEY,
    kategori_id INTEGER REFERENCES kategori_materi(id_kategori_materi),
    judul VARCHAR(200) NOT NULL,
    deskripsi TEXT NOT NULL,
    phrases TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Function untuk generate nomor referensi otomatis
CREATE OR REPLACE FUNCTION generate_reference_number()
RETURNS TRIGGER AS $$
DECLARE
    ref_prefix TEXT := 'PPK';
    year_code TEXT := to_char(CURRENT_DATE, 'YY');
    month_code TEXT := to_char(CURRENT_DATE, 'MM');
    day_code TEXT := to_char(CURRENT_DATE, 'DD');
    seq_number TEXT;
    full_ref TEXT;
    is_unique BOOLEAN := FALSE;
    attempt_count INTEGER := 0;
    max_attempts INTEGER := 100;
BEGIN
    WHILE NOT is_unique AND attempt_count < max_attempts LOOP
        attempt_count := attempt_count + 1;
        
        -- Generate 3-digit sequence number (100-999)
        seq_number := LPAD(CAST(floor(random() * 900 + 100) AS TEXT), 3, '0');
        
        -- Format: PPKS-YYMMDDXXX
        full_ref := ref_prefix || '-' || year_code || month_code || day_code || seq_number;
        
        PERFORM 1 FROM laporan_kasus 
        WHERE nomor_referensi = full_ref 
        AND deleted_at IS NULL;
        
        IF NOT FOUND THEN
            is_unique := TRUE;
        END IF;
    END LOOP;
    
    IF NOT is_unique THEN
        RAISE EXCEPTION 'Failed to generate unique reference number after % attempts', max_attempts;
    END IF;
    
    NEW.nomor_referensi := full_ref;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Function untuk auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function untuk soft delete
CREATE OR REPLACE FUNCTION soft_delete_record(
    table_name TEXT, 
    record_id INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
    sql_query TEXT;
    rows_affected INTEGER;
BEGIN
    -- Validate table name untuk security
    IF table_name NOT IN ('laporan_kasus', 'kategori_pelapor', 'status', 'kategori_materi', 'materi') THEN
        RAISE EXCEPTION 'Invalid table name: %', table_name;
    END IF;
    
    -- Build dynamic query
    sql_query := format('UPDATE %I SET deleted_at = CURRENT_TIMESTAMP WHERE id_%s = $1 AND deleted_at IS NULL', 
                       table_name, 
                       CASE 
                           WHEN table_name = 'laporan_kasus' THEN 'laporan'
                           WHEN table_name = 'kategori_pelapor' THEN 'kategori_pelapor'
                           WHEN table_name = 'status' THEN 'status'
                           WHEN table_name = 'kategori_materi' THEN 'kategori_materi'
                           WHEN table_name = 'materi' THEN 'materi'
                       END);
    
    EXECUTE sql_query USING record_id;
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    RETURN rows_affected > 0;
END;
$$ LANGUAGE plpgsql;

-- Function untuk restore soft deleted record
CREATE OR REPLACE FUNCTION restore_record(
    table_name TEXT, 
    record_id INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
    sql_query TEXT;
    rows_affected INTEGER;
BEGIN
    -- Validate table name
    IF table_name NOT IN ('laporan_kasus', 'kategori_pelapor', 'status', 'kategori_materi', 'materi') THEN
        RAISE EXCEPTION 'Invalid table name: %', table_name;
    END IF;
    
    -- Build dynamic query
    sql_query := format('UPDATE %I SET deleted_at = NULL WHERE id_%s = $1 AND deleted_at IS NOT NULL', 
                       table_name,
                       CASE 
                           WHEN table_name = 'laporan_kasus' THEN 'laporan'
                           WHEN table_name = 'kategori_pelapor' THEN 'kategori_pelapor'
                           WHEN table_name = 'status' THEN 'status'
                           WHEN table_name = 'kategori_materi' THEN 'kategori_materi'
                           WHEN table_name = 'materi' THEN 'materi'
                       END);
    
    EXECUTE sql_query USING record_id;
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    RETURN rows_affected > 0;
END;
$$ LANGUAGE plpgsql;

-- Trigger untuk auto-update updated_at di semua tabel
CREATE TRIGGER update_kategori_pelapor_updated_at
    BEFORE UPDATE ON kategori_pelapor
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_status_updated_at
    BEFORE UPDATE ON status
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_kategori_materi_updated_at
    BEFORE UPDATE ON kategori_materi
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_materi_updated_at
    BEFORE UPDATE ON materi
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_laporan_kasus_updated_at
    BEFORE UPDATE ON laporan_kasus
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger untuk generate nomor referensi
CREATE TRIGGER set_reference_number
    BEFORE INSERT ON laporan_kasus
    FOR EACH ROW
    EXECUTE FUNCTION generate_reference_number();

-- Insert kategori pelapor
INSERT INTO kategori_pelapor (kategori, deskripsi) VALUES 
('korban', 'Orang yang mengalami kekerasan secara langsung'),
('saksi', 'Orang yang menyaksikan atau mengetahui terjadinya kekerasan');

-- Insert status terlapor  
INSERT INTO status (status, deskripsi) VALUES 
('mahasiswa', 'Mahasiswa aktif di lingkungan kampus'),
('dosen', 'Dosen tetap, kontrak, atau dosen luar biasa'),
('staf', 'Tenaga kependidikan dan administrasi'),
('warga kampus', 'Warga kampus lainnya (kontraktor, vendor, dll)'),
('masyarakat umum', 'Masyarakat umum di luar lingkungan kampus');

-- Insert kategori materi
INSERT INTO kategori_materi (kategori, deskripsi) VALUES 
('definisi dan konsep', 'Pengertian dasar dan konsep fundamental dalam pencegahan dan penanganan kekerasan di lingkungan perguruan tinggi'),
('bentuk', 'Berbagai bentuk dan jenis kekerasan'),
('hak dan perlingungan', 'Hak korban, saksi, dan perlindungan hukum'),
('Tata cara penanganan', 'Tata cara pelaporan dan penanganan kasus'),
('sanksi', 'Sanksi akademik dan hukum untuk pelaku'),
('satgas', 'Peran dan fungsi Satuan Tugas (Satgas) dalam penanganan kasus kekerasan'),
('pencegahan dan penanganan', 'Upaya pencegahan dan penanganan kekerasan di perguruan tinggi'),
('lainnya', 'Materi lain yang relevan dengan pencegahan dan penanganan kekerasan di perguruan tinggi');

INSERT INTO materi (kategori_id, judul, deskripsi, phrases) VALUES 
(1,'Pengertian kekerasan','Kekerasan adalah segala tindakan yang dilakukan oleh seseorang, baik menggunakan kekuatan fisik maupun tidak, yang dapat membahayakan tubuh atau nyawa orang lain, menyebabkan penderitaan fisik, seksual, atau psikologis, serta mengambil kebebasan seseorang, termasuk tindakan yang membuat korban pingsan atau tidak berdaya untuk melawan.',ARRAY['definisi kekerasan', 'arti kekerasan', 'tindak kekerasan', 'pengertian kekerasan']),
(1,'Pengertian pencegahan','Pencegahan adalah upaya, tindakan, atau langkah-langkah yang dilakukan untuk mengantisipasi dan menghindari terjadinya kekerasan di lingkungan perguruan tinggi. Tujuannya memastikan agar individu atau kelompok tidak melakukan tindakan kekerasan dalam bentuk apapun di kampus.',ARRAY['definisi pencegahan', 'arti pencegahan', 'upaya preventif', 'antisipasi kekerasan', 'langkah pencegahan', 'tindakan preventif', 'hindari kekerasan', 'cegah kekerasan']),
(1,'Pengertian penanganan','Penanganan adalah rangkaian tindakan, langkah-langkah, atau proses yang dilakukan untuk merespon, mengatasi, dan menyelesaikan kasus kekerasan yang telah terjadi di lingkungan perguruan tinggi. Ini mencakup proses pelaporan, pemeriksaan, hingga penetapan keputusan.',ARRAY['definisi penanganan', 'arti penanganan', 'respon kekerasan', 'atasi kekerasan', 'proses investigasi', 'tindakan responsif', 'langkah penanganan', 'selesaikan kasus', 'penyelidikan kejadian']),
(1,'Pengertian pelapor','Pelapor adalah setiap orang yang menyampaikan laporan atau informasi mengenai kejadian kekerasan yang dialaminya secara langsung atau yang diketahuinya telah terjadi di lingkungan perguruan tinggi. Pelapor dapat berupa korban kekerasan itu sendiri atau pihak lain yang mengetahui adanya dugaan kekerasan',ARRAY['definisi pelapor', 'arti pelapor', 'saksi kejadian', 'pemberi informasi', 'korban kekerasan', 'pelapor kasus', 'penyampai laporan', 'saksi kekerasan', 'whistleblower kampus']),
(1,'pengertian terlapor','Terlapor adalah warga kampus, Pemimpin Perguruan Tinggi, dan/atau mitra Perguruan Tinggi yang diduga melakukan tindakan kekerasan dan dilaporkan oleh pelapor. Terlapor masih memiliki status praduga tidak bersalah sampai proses pemeriksaan selesai dan terbukti melakukan kekerasan.',ARRAY['definisi terlapor', 'arti terlapor', 'tersangka kekerasan', 'terduga pelaku', 'terlapor kasus', 'subjek laporan', 'pihak tertuduh', 'diduga pelaku', 'terdakwa kekerasan']),
(1,'pengertian korban','Korban adalah warga kampus dan mitra Perguruan Tinggi yang mengalami tindakan kekerasan. Mereka adalah individu yang secara langsung menerima dampak negatif baik secara fisik, psikis, seksual, atau bentuk kekerasan lainnya yang terjadi di lingkungan perguruan tinggi dan berhak mendapatkan perlindungan serta pemulihan.',ARRAY['definisi korban', 'arti korban', 'penyintas kekerasan', 'penerima kekerasan', 'korban tindakan', 'sasaran kekerasan', 'pengalami kekerasan', 'target kekerasan', 'pihak terdampak']),
(1,'pengertian saksi','Saksi adalah warga kampus dan masyarakat yang mendengar, melihat, dan/atau mengalami dugaan kekerasan di lingkungan perguruan tinggi. Saksi memiliki peran penting dalam proses penanganan kasus kekerasan dengan memberikan keterangan yang diketahuinya untuk mendukung proses pemeriksaan dan pembuktian.',ARRAY['definisi saksi', 'arti saksi', 'pemberi keterangan', 'pendengar kejadian', 'pelihat kekerasan', 'pengamat kekerasan', 'saksi mata', 'saksi pendengaran', 'pendukung pembuktian']),
(1,'pengertian pelaku','Pelaku adalah terlapor yang telah terbukti melakukan kekerasan terhadap korban berdasarkan hasil pemeriksaan dan proses penanganan kasus. Status pelaku didapatkan setelah melalui tahapan pemeriksaan lengkap dan dinyatakan bersalah, sehingga dapat dikenai sanksi administratif sesuai dengan tingkat pelanggaran yang dilakukannya.',ARRAY['definisi pelaku', 'arti pelaku', 'terbukti bersalah', 'penyebab kekerasan', 'individu bersalah', 'pembuat kekerasan', 'terhukum kasus', 'pelanggar aturan', 'terpidana kekerasan']),
(1,'pengertian warga kampus','Warga Kampus adalah dosen, tenaga kependidikan, dan mahasiswa yang terlibat dalam penyelenggaraan Tridharma Perguruan Tinggi. Mereka merupakan komponen utama dalam ekosistem perguruan tinggi yang ikut bertanggung jawab dalam menciptakan lingkungan pendidikan yang aman, nyaman, dan bebas dari kekerasan.',ARRAY['definisi warga kampus', 'arti warga kampus', 'komunitas akademik', 'civitas akademika', 'anggota kampus', 'komunitas kampus', 'masyarakat kampus', 'penghuni kampus', 'keluarga kampus', 'siapa warga kampus']),
(1,'maksud ppk','PPK adalah singkatan dari Pencegahan dan Penanganan Kekerasan di lingkungan Perguruan Tinggi. Berdasarkan Permen No. 55 Tahun 2024, upaya ini dimaksudkan untuk melindungi warga kampus dan mitra perguruan tinggi dari tindakan kekerasan, mencegah terjadinya kekerasan dalam pelaksanaan Tridharma, serta menciptakan lingkungan pendidikan yang ramah, aman, inklusif, setara, dan bebas dari segala bentuk kekerasan',ARRAY['maksud pencegahan dan penanganan', 'arti PPK', 'fungsi PPK', 'kegunaan PPK', 'manfaat PPK', 'landasan PPK', 'urgensi PPK']),
(1,'tujuan ppk','Tujuan Pencegahan dan Penanganan Kekerasan (PPK) di lingkungan Perguruan Tinggi adalah agar warga kampus, perguruan tinggi, dan mitra perguruan tinggi mampu mencegah terjadinya kekerasan, dapat melaporkan kekerasan yang dialami atau diketahui, dapat mencari dan mendapatkan bantuan ketika mengalami kekerasan, serta memastikan korban kekerasan segera mendapatkan penanganan dan bantuan yang menyeluruh untuk pemulihan.',ARRAY['tujuan pencegahan', 'sasaran PPK', 'arah PPK', 'target PPK', 'hasil PPK', 'capaian PPK', 'dampak PPK', 'manfaat PPK', 'fokus PPK']),
(1,'prinsip ppk','Pencegahan dan Penanganan Kekerasan (PPK) di lingkungan Perguruan Tinggi dilaksanakan dengan prinsip-prinsip penting, yaitu: nondiskriminasi (tidak membedakan berdasarkan identitas), kepentingan terbaik bagi korban, keadilan dan kesetaraan gender, kesetaraan hak bagi penyandang disabilitas, akuntabilitas, independen (bebas dari intervensi), kehati-hatian, konsisten, jaminan tidak berulang, dan keberlanjutan pendidikan bagi mahasiswa yang terlibat kasus.',ARRAY['prinsip pencegahan', 'prinsip penanganan', 'landasan PPK', 'nilai-nilai PPK', 'asas PPK', 'pedoman PPK', 'pilar PPK', 'fondasi PPK', 'acuan PPK', 'panduan PPK']),
(1,'sasaran ppk','Sasaran Pencegahan dan Penanganan Kekerasan (PPK) di lingkungan Perguruan Tinggi mencakup tiga komponen utama, yaitu Warga Kampus (dosen, tenaga kependidikan, dan mahasiswa), Pemimpin Perguruan Tinggi (rektor, ketua, direktur, atau jabatan setara), dan Mitra Perguruan Tinggi (badan hukum atau perseorangan yang bekerjasama dengan perguruan tinggi dalam pelaksanaan Tridharma). Ketiga komponen ini menjadi fokus upaya baik dalam aspek pencegahan maupun penanganan kekerasan.',ARRAY['sasaran pencegahan', 'target penanganan', 'objek PPK', 'kelompok sasaran', 'pihak terlindungi', 'subjek PPK', 'cakupan PPK', 'lingkup PPK', 'tujuan perlindungan', 'peserta dilindungi']),
(1,'Permendikbudristek No.55/2024','Peraturan Menteri Pendidikan, Kebudayaan, Riset, dan Teknologi Nomor 55 Tahun 2024 tentang Pencegahan dan Penanganan Kekerasan di Lingkungan Perguruan Tinggi menggantikan Permendikbud No.30 Tahun 2021. Peraturan ini memperluas cakupan dari kekerasan seksual menjadi semua bentuk kekerasan.',ARRAY['permendikbud', 'regulasi', 'peraturan menteri', 'kebijakan', 'dasar hukum', 'permen']),
(1,'Pengertian Mitra Kampus','Mitra Perguruan Tinggi adalah badan hukum atau perseorangan yang bekerja sama dengan Perguruan Tinggi dalam pelaksanaan Tridharma. Mitra kampus PNUP mencakup perusahaan industri yang menjadi tempat praktek kerja lapangan mahasiswa, institusi pendidikan yang menjalin kerjasama akademik, lembaga penelitian yang berkolaborasi dalam riset, organisasi masyarakat yang terlibat dalam pengabdian masyarakat, serta vendor atau penyedia jasa yang mendukung operasional kampus. Mitra kampus memiliki tanggung jawab dalam pencegahan dan penanganan kekerasan serta dapat dikenakan sanksi administratif jika terbukti melakukan kekerasan.',ARRAY['pengertian mitra kampus', 'definisi mitra', 'mitra perguruan tinggi', 'partner kampus', 'mitra PNUP', 'kerjasama kampus', 'vendor kampus', 'industri mitra', 'lembaga mitra', 'arti mitra', 'maksud mitra', 'mitra eksternal', 'stakeholder kampus', 'rekanan kampus']),
(2,'bentuk kekerasaan','Berdasarkan Permen No. 55 Tahun 2024, bentuk kekerasan di lingkungan perguruan tinggi diklasifikasikan menjadi enam jenis, yaitu: kekerasan fisik (perbuatan dengan kontak fisik langsung), kekerasan psikis (perbuatan non-fisik yang merendahkan atau menimbulkan tekanan mental), perundungan (pola perilaku kekerasan yang berulang), kekerasan seksual (perbuatan yang menyerang tubuh atau fungsi reproduksi), diskriminasi dan intoleransi (pembedaan berdasarkan identitas), serta kebijakan yang mengandung kekerasan (aturan yang berpotensi menimbulkan kekerasan). Bentuk-bentuk kekerasan ini dapat dilakukan secara langsung maupun tidak langsung melalui media elektronik atau non-elektronik.',ARRAY['jenis kekerasan', 'kategori kekerasan', 'tipe kekerasan', 'klasifikasi kekerasan', 'macam kekerasan', 'ragam kekerasan', 'wujud kekerasan', 'contoh kekerasan', 'model kekerasan', 'pola kekerasan']),
(2,'kekerasan fisik','Kekerasan fisik adalah setiap perbuatan yang melibatkan kontak fisik langsung, dilakukan dengan atau tanpa menggunakan alat bantu, yang dapat menyebabkan cedera, luka, atau bahaya pada tubuh korban. Bentuk kekerasan fisik di lingkungan perguruan tinggi dapat berupa tawuran antar mahasiswa, penganiayaan, perkelahian, eksploitasi ekonomi melalui kerja paksa untuk keuntungan pelaku, tindakan yang mengakibatkan pembunuhan, atau bentuk kontak fisik berbahaya lainnya yang dilarang menurut peraturan perundang-undangan.',ARRAY['kontak fisik', 'penganiayaan tubuh', 'cedera paksa', 'pukul korban', 'tawuran mahasiswa', 'kerja paksa', 'eksploitasi tubuh', 'lukai fisik', 'cedera langsung', 'penyiksaan badan']),
(2,'kekerasan psikis','Kekerasan psikis adalah setiap perbuatan non-fisik yang dilakukan dengan tujuan untuk merendahkan, menghina, menakuti, atau membuat korban merasa tidak nyaman secara mental dan emosional. Di lingkungan perguruan tinggi, kekerasan psikis dapat berupa pengucilan dari kelompok, penolakan tanpa alasan jelas, pengabaian yang disengaja, penghinaan verbal, penyebaran rumor atau gosip jahat, panggilan nama yang mengejek, intimidasi, teror, mempermalukan korban di depan umum, pemerasan, atau bentuk tekanan mental lainnya yang merusak kesejahteraan psikologis korban.',ARRAY['tekanan mental', 'hinaan verbal', 'pengucilan sosial', 'intimidasi psikis', 'teror mental', 'ejek individu', 'sebaran rumor', 'permalukan korban', 'sebar gosip', 'pemerasan psikologis']),
(2,'perundungan','Perundungan adalah pola perilaku negatif yang mencakup kekerasan fisik dan/atau psikis yang dilakukan secara berulang-ulang dan memiliki unsur ketimpangan relasi kuasa antara pelaku dan korban. Di lingkungan perguruan tinggi, perundungan dapat terjadi antar mahasiswa, antara dosen dengan mahasiswa, atau antar civitas akademika lainnya dimana pihak yang lebih kuat atau memiliki otoritas menyalahgunakan kekuasaannya untuk secara sistematis menekan, mengintimidasi, atau menyakiti pihak yang lebih lemah atau rentan.',ARRAY['bully kampus', 'intimidasi berulang', 'tekan sistematis', 'ganggu berkala', 'siksa berkelanjutan', 'cemooh terstruktur', 'hina berulang', 'intimidasi berkuasa', 'penindasan akademik', 'kekerasan sistematis']),
(2,'kekerasan seksual','Kekerasan seksual adalah perbuatan yang merendahkan, menghina, melecehkan, dan/atau menyerang tubuh atau fungsi reproduksi seseorang karena adanya ketimpangan relasi kuasa dan/atau gender. Tindakan ini berakibat atau berpotensi menimbulkan penderitaan fisik dan/atau psikis, mengganggu fungsi reproduksi, dan dapat menghilangkan kesempatan korban untuk melaksanakan pendidikan dengan aman dan optimal. Bentuknya beragam mulai dari ujaran seksual tidak diinginkan, pelecehan, hingga perkosaan dan eksploitasi seksual.',ARRAY['pelecehan seksual', 'serangan seksual', 'eksploitasi tubuh', 'intimidasi seksual', 'pemaksaan seksual', 'hinaan seksual', 'sentuhan paksa', 'komentar cabul', 'perkosaan kampus', 'percobaan perkosaan']),
(2,'diskriminasi dan intoleransi','Diskriminasi dan intoleransi adalah bentuk kekerasan yang melibatkan tindakan pembedaan, pengecualian, pembatasan, atau pemilihan berdasarkan identitas seseorang seperti suku/etnis, agama, kepercayaan, ras, warna kulit, usia, status sosial ekonomi, kebangsaan, afiliasi, ideologi, jenis kelamin, dan/atau kondisi fisik serta mental. Di lingkungan perguruan tinggi, ini dapat berupa larangan beribadah sesuai keyakinan, pemaksaan mengikuti kegiatan yang bertentangan dengan keyakinan, perlakuan berbeda dalam proses akademik, atau penghalangan akses terhadap hak dan fasilitas pendidikan.',ARRAY['perlakuan berbeda', 'pengecualian kelompok', 'pembatasan hak', 'pemilihan diskriminatif', 'penolakan identitas', 'paksaan keyakinan', 'halang akses', 'perbedaan perlakuan', 'eksklusi sistematis', 'marginalisasi individu']),
(2,'kebijakan yang mengandung kekerasan','Kebijakan yang mengandung kekerasan adalah peraturan, ketentuan, atau instruksi, baik tertulis maupun tidak tertulis, yang berpotensi atau menimbulkan terjadinya kekerasan di lingkungan perguruan tinggi. Kebijakan tertulis dapat berupa surat keputusan, surat edaran, nota dinas, pedoman, dan dokumen formal lainnya. Sedangkan kebijakan tidak tertulis meliputi imbauan, instruksi lisan, atau bentuk arahan lainnya yang meskipun tidak didokumentasikan, tetapi dapat menyebabkan atau memicu tindakan kekerasan terhadap warga kampus.',ARRAY['aturan berbahaya', 'ketentuan merugikan', 'kebijakan diskriminatif', 'peraturan memicu', 'instruksi menyakiti', 'edaran bermasalah', 'kebijakan intoleran', 'aturan memaksa', 'surat keputusan', 'instruksi berbahaya']),
(2,'jenis kekerasan fisik','Kekerasan fisik di lingkungan perguruan tinggi berdasarkan Permen No. 55 Tahun 2024 terbagi dalam beberapa jenis, yaitu: tawuran yang melibatkan perkelahian antar kelompok mahasiswa, penganiayaan terhadap individu yang menyebabkan cedera, perkelahian yang melibatkan kontak fisik langsung, eksploitasi ekonomi melalui kerja paksa untuk memberikan keuntungan bagi pelaku, pembunuhan atau tindakan yang mengakibatkan hilangnya nyawa, serta bentuk kontak fisik berbahaya lainnya yang dilarang dalam peraturan perundang-undangan. Semua jenis kekerasan fisik ini dapat terjadi dalam konteks kegiatan akademik maupun non-akademik.',ARRAY['tawuran kampus', 'penganiayaan mahasiswa', 'perkelahian akademik', 'eksploitasi tubuh', 'kerja paksa', 'cedera fisik', 'pembunuhan kampus', 'serangan langsung', 'kontak berbahaya', 'cedera memar']),
(2,'jenis kekerasan psikis','Jenis kekerasan psikis di lingkungan perguruan tinggi menurut Permen No. 55 Tahun 2024 meliputi berbagai bentuk tindakan non-fisik yang merusak kesehatan mental, yaitu: pengucilan dari kelompok sosial akademik, penolakan tanpa alasan yang jelas, pengabaian yang disengaja, penghinaan yang merendahkan martabat, penyebaran rumor atau informasi yang tidak benar, panggilan nama yang mengejek atau merendahkan, intimidasi yang menimbulkan ketakutan, teror yang berkelanjutan, perbuatan mempermalukan di depan umum, pemerasan atau pemaksaan untuk melakukan sesuatu, serta tindakan lain yang menimbulkan tekanan psikologis pada korban.',ARRAY['pengucilan sosial', 'tolak individu', 'abaikan sengaja', 'hina verbal', 'sebar rumor', 'julukan mengejek', 'intimidasi mental', 'teror psikologis', 'permalukan publik', 'merasa tertekan', 'tekanan akademik', 'pemaksaan kehendak']),
(2,'jenis kekerasan seksual','Berdasarkan Permen No. 55 Tahun 2024, kekerasan seksual di lingkungan perguruan tinggi mencakup berbagai tindakan, antara lain: ujaran diskriminatif atau melecehkan tentang fisik atau identitas gender, menunjukkan alat kelamin tanpa persetujuan, ucapan bernuansa seksual atau siulan, tatapan dengan nuansa seksual, pengiriman konten bernuansa seksual, pengambilan foto/video korban tanpa persetujuan, penyebaran informasi pribadi bernuansa seksual, pengintipan pada ruang pribadi, bujukan untuk kegiatan seksual, hukuman bernuansa seksual, sentuhan fisik tanpa persetujuan, pemaksaan aktivitas seksual, perkosaan, pemaksaan aborsi, pemaksaan sterilisasi, hingga perdagangan orang untuk eksploitasi seksual. Semua tindakan ini termasuk kekerasan seksual bila terjadi dalam konteks ketimpangan relasi kuasa.',ARRAY['pelecehan verbal', 'komentar tubuh', 'siulan menggoda', 'tatapan melecehkan', 'kirim konten', 'foto tanpa izin', 'intip pribadi', 'sentuh paksa', 'pemaksaan aborsi', 'buka pakaian', 'praktik perkosaan', 'eksploitasi seksual', 'bujuk seksual', 'intimidasi reproduksi']),
(2,'jenis diskriminasi dan intoleransi','Diskriminasi dan intoleransi di lingkungan perguruan tinggi menurut Permen No. 55 Tahun 2024 mencakup beberapa jenis, yaitu: larangan menggunakan pakaian sesuai keyakinan agama, larangan mengikuti mata kuliah agama yang sesuai keyakinan, larangan mengamalkan ajaran agama/kepercayaan, pemaksaan menggunakan pakaian yang tidak sesuai keyakinan, pemaksaan mengikuti mata kuliah agama yang tidak sesuai keyakinan, perlakuan berbeda berdasarkan latar belakang identitas, larangan atau pemaksaan mengikuti perayaan keagamaan, pembatasan akses pendidikan (seperti penerimaan mahasiswa, penggunaan sarana prasarana, beasiswa, kompetisi, penilaian, kelulusan), pembatasan hak dosen atau tenaga kependidikan, serta bentuk-bentuk diskriminasi dan intoleransi lainnya berdasarkan identitas seseorang.',ARRAY['larangan berjilbab', 'paksaan keagamaan', 'tolak keyakinan', 'batasi ibadah', 'diskriminasi etnis', 'halang beasiswa', 'tolak pendaftaran', 'nilai tidak adil', 'paksaan upacara', 'tolak kebudayaan', 'batasi kelulusan', 'kesempatan berbeda', 'halang penerimaan', 'batasi promosi', 'larangan berpakaian']),
(2,'ketimpangan relasi kuasa','Ketimpangan relasi kuasa menjadi penyebab terjadinya kekerasan khususnya perundungan, kekerasan seksual, dan diskriminasi/intoleransi. Ketimpangan ini terjadi ketika seseorang menyalahgunakan sumber daya yang dimilikinya seperti antara dosen dan mahasiswa, pimpinan dan staf, atau bahkan senior dan junior dalam organisasi kemahasiswaan.',ARRAY['ketimpangan relasi kuasa', 'relasi kuasa', 'penyalahgunaan kekuasaan', 'abuse of power', 'ketidakseimbangan kekuatan', 'dominasi kekuasaan', 'eksploitasi posisi', 'menyalahgunakan wewenang', 'kontrol berlebihan', 'tekanan hierarki', 'pengendalian orang lain', 'posisi superior', 'kekuasaan tidak seimbang', 'intimidasi jabatan', 'pressure dari atasan']),
(3,'Hak korban','Korban kekerasan di lingkungan perguruan tinggi memiliki sejumlah hak yang dilindungi berdasarkan Permen No. 55 Tahun 2024, meliputi: hak mendapatkan informasi tentang tahapan dan perkembangan penanganan kasus, perlindungan dari ancaman atau kekerasan lanjutan, perlindungan terhadap kerahasiaan identitas dan informasi kasus, akses penuh terhadap layanan pendidikan tanpa hambatan, perlindungan dari kehilangan pekerjaan (bagi dosen/tenaga kependidikan), informasi lengkap tentang hak dan fasilitas perlindungan yang tersedia, serta layanan pendampingan, perlindungan, dan pemulihan sesuai kebutuhan spesifik korban. Jika korban adalah penyandang disabilitas, pemenuhan hak-hak tersebut harus memperhatikan ragam disabilitasnya.',ARRAY['hak korban', 'perlindungan korban']),
(3,'Hak saksi','Saksi dalam kasus kekerasan memiliki hak-hak yang dilindungi oleh perguruan tinggi, mencakup perlindungan kerahasiaan identitas, perlindungan dari ancaman atau kekerasan, akses layanan pendidikan, perlindungan dari potensi kehilangan pekerjaan, penyediaan informasi mengenai hak dan fasilitas perlindungan, serta layanan pendampingan, pelindungan, dan/atau pemulihan sesuai kebutuhannya.',ARRAY['hak saksi', 'perlindungan saksi']),
(3,'hak terlapor','Terlapor dalam kasus kekerasan memiliki hak-hak yang dilindungi, termasuk hak atas informasi perkembangan penanganan laporan, perlindungan kerahasiaan identitas dan informasi kasus, layanan pendampingan khusus bagi terlapor penyandang disabilitas atau berusia anak, serta hak pemulihan nama baik apabila laporan dugaan kekerasan tidak terbukti.',ARRAY['hak terlapor', 'perlindungan terlapor']),
(3,'hal pelapor','Pelapor dalam kasus kekerasan memiliki hak-hak yang dilindungi oleh perguruan tinggi, mencakup hak untuk mendapatkan informasi tentang tahapan dan perkembangan penanganan laporan, perlindungan dari ancaman atau kekerasan, perlindungan atas kerahasiaan identitas, akses layanan pendidikan, perlindungan dari potensi kehilangan pekerjaan, penyediaan informasi mengenai hak dan fasilitas perlindungan, serta layanan pendampingan dan pemulihan sesuai kebutuhannya.',ARRAY['hak pelapor', 'perlindungan pelapor']),
(3,'Kerahasiaan identitas','Satuan Tugas berkewajiban merahasiakan identitas pihak yang terkait langsung dengan laporan. Korban, saksi, pelapor, dan terlapor berhak atas perlindungan kerahasiaan identitas dan informasi kasus untuk melindungi dari ancaman atau kekerasan lebih lanjut.',ARRAY['kerahasiaan', 'identitas aman', 'privasi', 'rahasia identitas', 'proteksi data']),
(3,'Perlindungan saksi dan korban','korban dan saksi berhak atas: perlindungan dari ancaman atau kekerasan oleh terlapor, perlindungan dari berulangnya kekerasan, akses layanan pendidikan, perlindungan dari kehilangan pekerjaan, dan layanan pendampingan serta pemulihan sesuai kebutuhan.',ARRAY['perlindungan saksi', 'perlindungan korban', 'proteksi saksi', 'keamanan korban', 'jaminan keselamatan']),
(4,'tata cara penanganan','Tata cara penanganan kekerasan dilakukan melalui serangkaian tahapan sistematis yang meliputi pelaporan, tindak lanjut pelaporan, pemeriksaan, penyusunan kesimpulan dan rekomendasi, serta tindak lanjut kesimpulan dan rekomendasi. Proses ini dapat dilakukan baik oleh Perguruan Tinggi melalui Satuan Tugas untuk kasus yang melibatkan non-pimpinan, maupun oleh Kementerian melalui Inspektorat Jenderal untuk kasus yang melibatkan pimpinan perguruan tinggi.',ARRAY['prosedur penanganan', 'alur pelaporan', 'tahapan pemeriksaan', 'proses hukum', 'mekanisme penyelesaian']),
(4,'pelaporan','Pelaporan adalah proses penyampaian informasi tentang dugaan kekerasan yang dapat dilakukan oleh siapapun kepada Satuan Tugas, Perguruan Tinggi, atau Inspektorat Jenderal. Pelaporan bisa dilakukan secara langsung dengan datang ke tempat atau tidak langsung melalui surat, telepon, pesan elektronik, email atau cara lain yang memudahkan. Dalam melaporkan, minimal harus mencantumkan identitas pelapor dan terlapor, waktu dan tempat kejadian, serta uraian dugaan kekerasan, tanpa harus menyertakan bukti awal.',ARRAY['mekanisme pelaporan kekerasan', 'cara melaporkan kekerasan', 'prosedur pelaporan dugaan', 'sistem pelaporan kampus', 'proses pengaduan kekerasan', 'alur pelaporan kampus', 'mekanisme pelaporan', 'cara melapor', 'sistem pelaporan']),
(4,'tindak lanjut pelaporan','Tindak lanjut pelaporan harus dilakukan dalam waktu 3 hari setelah laporan diterima dan selesai maksimal 7 hari. Prosesnya terdiri dari penelaahan materi (identifikasi korban/saksi/terlapor, bentuk kekerasan, kronologi, bukti, dan kebutuhan pendampingan) dan penyusunan rencana tindak lanjut pemeriksaan. Hasil penelaahan akan menentukan apakah kasus termasuk kekerasan sesuai Pasal 7 atau pelanggaran disiplin/etik. Jika terbukti kekerasan akan dilanjutkan pemeriksaan, jika bukan akan diberikan rekomendasi ke pihak berwenang.',ARRAY['proses tindak lanjut', 'penelaahan kasus kekerasan', 'rencana pemeriksaan laporan', 'mekanisme tindak lanjut', 'verifikasi dugaan kekerasan', 'identifikasi kasus kekerasan']),
(4,'pemeriksaan','Pemeriksaan dilakukan oleh Satuan Tugas atau Inspektorat Jenderal dalam waktu 30 hari dan dapat diperpanjang 30 hari. Pemeriksaan dilakukan terhadap pelapor, korban, saksi, terlapor dan pihak terkait untuk mengumpulkan keterangan dan bukti. Proses ini dilakukan secara tertutup, dengan pemberitahuan 3 hari sebelumnya. Terlapor diberi 3 kali kesempatan hadir, jika tidak hadir pemeriksaan tetap dilanjutkan. Untuk penyandang disabilitas, disediakan pendamping khusus. Hasil pemeriksaan dituangkan dalam berita acara yang ditandatangani pemeriksa dan terperiksa.',ARRAY['proses pemeriksaan kekerasan', 'waktu pemeriksaan dugaan', 'mekanisme berita acara', 'alur pemeriksaan kekerasan', 'prosedur permintaan keterangan', 'tata cara pemeriksaan']),
(4,'penyusunan kesimpulan dan rekomendasi','Penyusunan kesimpulan dan rekomendasi dilakukan maksimal 3 hari setelah pemeriksaan selesai dan harus diselesaikan dalam waktu 7 hari. Hasil kesimpulan berisi pernyataan dugaan kekerasan terbukti atau tidak terbukti. Jika tidak terbukti, rekomendasinya berupa pemulihan nama baik terlapor, keberlanjutan pendidikan/pekerjaan, dan pemulihan psikis. Jika terbukti, rekomendasinya berupa sanksi administratif, pendampingan korban/saksi, keberlanjutan pendidikan/pekerjaan korban, program konseling bagi pelaku, dan/atau pembatalan kebijakan yang mengandung kekerasan. Rekomendasi mempertimbangkan hal yang meringankan dan memberatkan.',ARRAY['hasil pemeriksaan kekerasan', 'kesimpulan dan rekomendasi', 'penyusunan sanksi administratif', 'rekomendasi tindak lanjut', 'bentuk sanksi pelaku', 'mekanisme kesimpulan pemeriksaan']),
(4,'tindak lanjut kesimpulan dan rekomendasi','Pemimpin Perguruan Tinggi atau badan penyelenggara wajib menindaklanjuti kesimpulan dan rekomendasi dengan menerbitkan keputusan dalam waktu 5 hari. Keputusan tersebut berisi pernyataan dugaan kekerasan terbukti atau tidak terbukti. Jika tidak terbukti, keputusan mencantumkan pemulihan nama baik terlapor. Jika terbukti, keputusan mencantumkan ketentuan yang dilanggar dan sanksi administratif. Salinan keputusan disampaikan kepada terlapor/pelaku, korban/pelapor, dan pejabat yang menangani sumber daya manusia jika terlapor adalah Pemimpin Perguruan Tinggi.',ARRAY['keputusan tindak lanjut', 'penerbitan sanksi administratif', 'penyampaian hasil pemeriksaan', 'penetapan sanksi pelaku', 'mekanisme tindak lanjut', 'hasil kesimpulan pemeriksaan']),
(4,'Layanan Pelaporan','Mahasiswa dan civitas akademika PNUP dapat melaporkan dugaan kekerasan melalui beberapa cara: 1) Chatbot PPKPT PNUP - Melaporkan melalui asisten virtual Satgas PPKPT PNUP yang tersedia 24/7 di [PLATFORM CHATBOT] dengan proses yang dipandu dan menjamin kerahasiaan. 2) Lapor Langsung - Datang ke sekretariat Satgas PPKPT PNUP di AD-123 atau menemui anggota Satgas secara langsung. 3) Telepon - Menghubungi hotline Satgas PNUP di wa.me/6281355060444. 4) Email - Mengirim laporan ke email resmi ppks@poliupg.ac.id dengan melampirkan identitas dan kronologi kejadian. ',ARRAY['layanan pelaporan', 'fasilitas pelaporan', 'kanal pelaporan', 'channel laporan', 'platform pelaporan', 'jalur pelaporan', 'akses pelaporan', 'kontak pelaporan', 'hotline', 'sekretariat satgas', 'chatbot laporan', 'email laporan', 'whatsapp laporan', 'cara kontak']),
(5,'sanksi ringan','Sanksi administratif tingkat ringan diberikan dalam dua bentuk. Untuk dosen dan tenaga kependidikan non ASN, sanksinya berupa teguran tertulis atau pernyataan permohonan maaf secara tertulis dari pelaku kepada korban. Untuk mahasiswa, sanksinya juga berupa teguran tertulis atau pernyataan permohonan maaf secara tertulis kepada korban. Sedangkan untuk Mitra Perguruan Tinggi, sanksinya berupa teguran tertulis atau pernyataan permohonan maaf secara tertulis dari pelaku kepada korban dan Perguruan Tinggi.',ARRAY['teguran tertulis pelaku', 'permohonan maaf tertulis', 'bentuk sanksi ringan', 'sanksi administratif ringan', 'mekanisme sanksi ringan', 'pemberian sanksi ringan']),
(5,'sanksi sedang','Sanksi administratif tingkat sedang memiliki bentuk berbeda untuk setiap pihak. Untuk dosen dan tenaga kependidikan non ASN, sanksinya berupa penurunan jenjang jabatan akademik atau jabatan fungsional selama 12 bulan. Untuk mahasiswa, sanksinya dapat berupa penundaan mengikuti perkuliahan, pencabutan beasiswa, atau pengurangan hak lain sesuai ketentuan. Untuk Mitra Perguruan Tinggi, sanksinya berupa penghentian sementara kerja sama dengan Perguruan Tinggi.',ARRAY['penurunan jabatan akademik', 'penundaan perkuliahan mahasiswa', 'pencabutan beasiswa mahasiswa', 'penghentian kerjasama sementara', 'sanksi administratif sedang', 'pemberian sanksi sedang']),
(5,'sanksi berat','Sanksi administratif tingkat berat merupakan sanksi terberat yang diberikan. Untuk dosen dan tenaga kependidikan non ASN, sanksinya berupa pemberhentian tetap sebagai dosen dan tenaga kependidikan, termasuk penonaktifan nomor unik pendidik. Untuk mahasiswa, sanksinya berupa pemberhentian tetap sebagai mahasiswa. Untuk Mitra Perguruan Tinggi, sanksinya berupa pemutusan kerja sama dengan Perguruan Tinggi.',ARRAY['pemberhentian tetap pegawai', 'pemutusan kerjasama perguruan', 'pemberhentian tetap mahasiswa', 'sanksi administratif berat', 'penonaktifan nomor pendidik', 'pemberhentian pemimpin perguruan']),
(5,'Jenis Sanksi Mahasiswa','Sanksi administratif bagi mahasiswa pelaku kekerasan diberlakukan dengan bertingkat dan disesuaikan dengan bobot pelanggaran yang dilakukan. Tingkat sanksi dimulai dari sanksi ringan seperti teguran tertulis atau pernyataan permintaan maaf, hingga sanksi berat berupa pemberhentian tetap sebagai mahasiswa. Sanksi tingkat sedang dapat berupa penundaan mengikuti perkuliahan, pencabutan beasiswa, atau pengurangan hak sesuai peraturan perundangan.',ARRAY['jenis sanksi mahasiswa', 'sanksi mahasiswa', 'hukuman mahasiswa', 'sanksi akademik', 'sanksi tingkat ringan', 'sanksi tingkat sedang', 'sanksi tingkat berat', 'teguran tertulis', 'skorsing', 'pencabutan beasiswa', 'drop out', 'dikeluarkan', 'pemberhentian mahasiswa', 'sanksi DO', 'hukuman akademik']),
(5,'Jenis Sanksi Dosen/Tendik','Sanksi bagi dosen dan tenaga kependidikan PNUP dibedakan berdasarkan status kepegawaian. Untuk dosen/tendik ASN (PNS) mengikuti ketentuan peraturan kepegawaian ASN yang berlaku. Untuk dosen/tendik non-ASN terdapat sanksi ringan berupa teguran tertulis atau permohonan maaf, sanksi sedang berupa penurunan jabatan selama 12 bulan, dan sanksi berat berupa pemberhentian tetap serta penonaktifan NUPTK melalui sistem Kemendikbud.',ARRAY['jenis sanksi dosen', 'sanksi tenaga kependidikan', 'sanksi tendik', 'sanksi ASN', 'sanksi non-ASN', 'penurunan jabatan', 'pemberhentian dosen', 'sanksi pegawai', 'hukuman dosen', 'sanksi kepegawaian']),
(5,'Sanksi Mitra Kampus','Sanksi administratif bagi mitra kampus yang terbukti melakukan kekerasan terdiri dari sanksi ringan berupa teguran tertulis atau pernyataan permohonan maaf secara tertulis dari pelaku kepada korban dan perguruan tinggi, sanksi sedang berupa penghentian sementara kerjasama dengan perguruan tinggi, dan sanksi berat berupa pemutusan kerjasama dengan perguruan tinggi.',ARRAY['sanksi mitra kampus', 'sanksi mitra', 'hukuman mitra', 'sanksi vendor', 'sanksi rekanan', 'pemutusan kerjasama', 'penghentian kerjasama', 'sanksi partner', 'blacklist mitra', 'sanksi eksternal', 'konsekuensi mitra', 'tindakan mitra', 'putus kontrak']),
(6,'tugas satgas','Satuan Tugas bertugas melaksanakan pencegahan dan penanganan kekerasan dengan fungsi: membantu menyusun pedoman, sosialisasi kesetaraan gender, menerima dan menindaklanjuti laporan, koordinasi dengan unit layanan disabilitas, memfasilitasi rujukan layanan, dan memantau pelaksanaan rekomendasi.',ARRAY['tugas satgas', 'fungsi satgas', 'wewenang', 'tanggung jawab', 'job desc']),
(6,'tugas dan fungsi satgas','Satuan Tugas memiliki beberapa fungsi yaitu membantu menyusun pedoman pencegahan dan penanganan kekerasan, melakukan sosialisasi tentang kesetaraan gender dan hak disabilitas, menerima dan menindaklanjuti laporan, menangani temuan dugaan kekerasan, koordinasi dengan unit layanan disabilitas, memfasilitasi rujukan layanan untuk korban/saksi, memantau pelaksanaan rekomendasi, dan menyampaikan laporan kegiatan ke Pemimpin Perguruan Tinggi minimal setahun sekali. Laporan ini berisi kegiatan pencegahan yang sudah dilakukan, data pelaporan, kegiatan penanganan yang sudah/sedang dilakukan, dan kegiatan fasilitasi pendampingan korban/saksi.',ARRAY['fungsi satgas', 'peran satuan tugas', 'fungsi pencegahan kekerasan', 'pelaksana tugas satgas', 'fungsi penanganan satgas']),
(6,'wewenang satgas','Dalam menjalankan tugas dan fungsinya, Satuan Tugas memiliki lima wewenang. Pertama, memanggil dan meminta keterangan dari pelapor, korban, saksi, terlapor, pendamping, dan/atau ahli. Kedua, meminta bantuan Pemimpin Perguruan Tinggi untuk menghadirkan pihak yang diperiksa. Ketiga, melakukan konsultasi mengenai penanganan kekerasan dengan pihak terkait dengan mempertimbangkan kondisi korban. Keempat, melakukan koordinasi dengan Perguruan Tinggi lain atau Mitra Perguruan Tinggi jika kasus melibatkan pihak dari luar. Kelima, memfasilitasi korban dan/atau pelapor kepada aparat penegak hukum jika diperlukan.',ARRAY['wewenang satgas perguruan', 'kewenangan satuan tugas', 'otoritas satgas kampus', 'kekuasaan satgas perguruan', 'wewenang penanganan kekerasan']),
(6,'Struktur Satgas ','Satgas PPKPT PNUP periode 2025/2027 terdiri dari [JUMLAH] anggota yang berasal dari berbagai unit di lingkungan PNUP. Ketua: Dr. Andi Musdariah S.S, M.Hum. Sekretaris: [NAMA SEKRETARIS]. Anggota: [NAMA ANGGOTA 1] , [NAMA ANGGOTA 2], [NAMA ANGGOTA 3]',ARRAY['struktur satgas', 'organisasi satgas', 'susunan tim', 'komposisi satgas', 'struktur organisasi', 'anggota satgas', 'ketua satgas', 'personil satgas']),
(7,'Tips mencegah kekerasan','Pencegahan dilakukan melalui: pembatasan pertemuan di luar jam operasional, panduan komunikasi antar warga kampus, pakta integritas anti kekerasan, dan panduan kerjasama dengan mitra yang memuat komitmen PPKPT. Edukasi kesetaraan gender dan nilai anti kekerasan juga menjadi kunci pencegahan.',ARRAY['tips pencegahan', 'cara mencegah', 'antisipasi', 'preventif', 'cegah kekerasan']);