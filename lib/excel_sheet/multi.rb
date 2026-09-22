# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — classeur Excel à plusieurs onglets.
#
# `ExcelSheet` crée son unique feuille dans `initialize` et ferme le classeur
# dans `gen_footer` : il ne sait faire qu'un onglet. Plutôt que de recopier sa
# fabrique de formats — qui divergerait à la première correction amont — on
# réaffecte les quatre variables que ses générateurs consultent, puis on les
# rejoue par feuille.
#
# Le couplage porte donc sur des noms de variables d'instance de la classe
# mère. C'est délibéré, et c'est ce qui garde ce fichier court ; une mise à jour
# Zammad qui les renommerait casserait bruyamment plutôt qu'en silence.
class ExcelSheet::Multi < ExcelSheet
  # Contraintes du format xlsx : au-delà, ou avec l'un de ces caractères,
  # `write_xlsx` lève — au moment du `send_data`, donc en production et jamais
  # en recette. Les noms viennent de libellés saisis par un administrateur.
  MAX_SHEET_NAME  = 31
  FORBIDDEN_CHARS = %r{[\[\]:*?/\\]}

  def initialize(title:, locale:, timezone: nil)
    super(title:, locale:, timezone:, header: [], records: [])
    @sheet_names = []
    # La feuille créée par la classe mère sert au premier onglet.
    @pending_worksheet = @worksheet
  end

  def add_sheet(name:, header:, records:, title: nil)
    sheet_name = safe_name(name)

    if @pending_worksheet
      # La classe mère a déjà créé une feuille, sans nom choisi, et `write_xlsx`
      # n'expose aucun moyen de la renommer ensuite. La laisser s'appeler
      # « Sheet1 » serait visible à l'ouverture ; la laisser vide en créerait
      # une de trop. On écrit donc directement le nom, après l'avoir validé
      # ici — c'est `add_worksheet` qui s'en chargerait sinon.
      @worksheet = @pending_worksheet
      @worksheet.instance_variable_set(:@name, sheet_name)
      @pending_worksheet = nil
    else
      @worksheet = @workbook.add_worksheet(sheet_name)
    end

    @title       = title || name
    @header      = header
    @records     = records
    @current_row = 0

    gen_header
    gen_rows
    self
  end

  # Le pied de page n'est écrit qu'une fois, sur la dernière feuille remplie,
  # et c'est lui qui ferme le classeur.
  def content
    gen_footer
    contents
  end

  private

  # Un nom déjà pris ferait lever `write_xlsx` : on suffixe plutôt que de
  # renoncer à l'onglet.
  def safe_name(name)
    base = name.to_s.gsub(FORBIDDEN_CHARS, ' ').strip.first(MAX_SHEET_NAME)
    base = 'Feuille' if base.blank?

    candidate = base
    suffix    = 1
    while @sheet_names.include?(candidate)
      suffix += 1
      marker = " (#{suffix})"
      candidate = base.first(MAX_SHEET_NAME - marker.length) + marker
    end

    @sheet_names << candidate
    candidate
  end
end
