# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — mise en page des e-mails (demandeurs et agents).
#
# Les corps d'e-mail restent des fragments HTML simples : ceux des déclencheurs
# passent par le nettoyeur HTML de Zammad, qui retire presque tous les styles
# (et, de toute façon, un corps de déclencheur doit rester lisible dans le fil
# du ticket). Ils portent seulement des CLASSES (`odice-title`, `odice-btn`,
# `odice-card`, `odice-rating`…), que le nettoyeur conserve.
#
# Au moment de construire l'e-mail (Channel::EmailBuild.build), un corps qui
# contient un élément `.odice-mail` est mis en forme ici : styles en ligne
# (les messageries ignorent ou réécrivent les feuilles de style), boutons en
# tableau (rendu identique sous Outlook), en-tête avec le logo, pied de page.
# Le fil du ticket garde la version simple ; seul l'e-mail envoyé change.
module Odice::MailLayout
  NAVY    = '#0c3258'.freeze
  PRIMARY = '#134c82'.freeze
  CYAN    = '#27a9ce'.freeze
  TEXT    = '#414042'.freeze
  MUTED   = '#6e7274'.freeze
  BORDER  = '#dde2e4'.freeze
  CANVAS  = '#eef2f6'.freeze
  SOFT    = '#f1f5f9'.freeze
  FONT    = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif".freeze

  # Du rouge au vert, adoucis pour rester lisibles en texte blanc.
  NOTES = {
    1 => ['#c83433', '#ffffff'],
    2 => ['#e07b39', '#ffffff'],
    3 => ['#e8b931', '#3a2f00'],
    4 => ['#62b37f', '#ffffff'],
    5 => ['#2e8b57', '#ffffff'],
  }.freeze

  P_STYLE = "margin:0 0 14px;font-family:#{FONT};font-size:15px;line-height:1.6;color:#{TEXT};".freeze

  # Branché sur Channel::EmailBuild.build par config/initializers/odice_mail.rb.
  module EmailBuildHook
    def build(attr, notification = false)
      if attr[:content_type] == 'text/html' && attr[:body].to_s.include?('odice-mail')
        attr = attr.merge(body: Odice::MailLayout.render(attr[:body]))
      end
      super
    end
  end

  module_function

  def render(html)
    fragment = Nokogiri::HTML::DocumentFragment.parse(html.to_s)
    root     = fragment.at_css('.odice-mail')
    return html if !root

    preheader = take(root, '.odice-preheader')&.text.to_s.squish
    title     = take(root, '.odice-title')&.inner_html.to_s.strip
    signature = take(root, '.odice-signature')&.inner_html.to_s.strip
    footnote  = take(root, '.odice-footnote')&.inner_html.to_s.strip

    style_content(root)
    page(preheader:, title:, content: root.inner_html, signature:, footnote:)
  rescue => e
    Rails.logger.error "Odice::MailLayout: #{e.class}: #{e.message}"
    html
  end

  def take(root, selector)
    node = root.at_css(selector)
    node&.remove
    node
  end

  def style_content(root)
    # Les gabarits de notification Zammad séparent leurs blocs par des <br> :
    # les marges des paragraphes les remplacent.
    root.xpath('./br').each(&:remove)
    root.css('a[target="zammad_app"]').each { |link| link['class'] = "#{link['class']} odice-btn".strip }

    root.css('.odice-rating').each { |node| node.replace(rating(node)) }
    root.css('a.odice-btn').each { |node| button_paragraph(node) }
    root.css('.odice-card').each { |node| node.replace(card(node)) }

    root.css('h2, .odice-subtitle').each do |node|
      node.name = 'h2'
      node['style'] = "margin:24px 0 6px;font-family:#{FONT};font-size:17px;line-height:1.4;font-weight:700;color:#{NAVY};"
    end
    root.css('p, div:not([style])').each do |node|
      next if node['style'].present?

      node['style'] = node['class'].to_s.include?('odice-muted') ? P_STYLE.sub('15px', '13px').sub(TEXT, MUTED) : P_STYLE
    end
    root.css('a:not([style])').each { |node| node['style'] = "color:#{PRIMARY};font-weight:600;text-decoration:underline;" }
    root.css('blockquote').each do |node|
      node['style'] = "margin:0 0 16px;padding:10px 14px;border-left:3px solid #{CYAN};background:#{SOFT};color:#{TEXT};font-family:#{FONT};font-size:14px;line-height:1.55;"
    end
  end

  # Bouton « bulletproof » : un tableau, pour qu'Outlook garde fond et marges.
  def button_paragraph(link)
    label = link.inner_html
    href  = link['href']
    table = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" style="display:table;width:auto;margin:6px 0 20px;border-collapse:separate;">
        <tr><td bgcolor="#{PRIMARY}" style="padding:0;border-radius:8px;background:#{PRIMARY};">
          <a href="#{ERB::Util.html_escape(href)}" style="display:inline-block;padding:12px 24px;font-family:#{FONT};font-size:15px;font-weight:700;line-height:1.2;color:#ffffff;text-decoration:none;border-radius:8px;">#{label}</a>
        </td></tr>
      </table>
    HTML
    container = link.ancestors('p, div').first
    if container && container.text.strip == link.text.strip && container.parent
      container.replace(table)
    else
      link.replace(table)
    end
  end

  def card(node)
    label = node.at_css('.odice-card-label')&.inner_html
    head  = node.at_css('.odice-card-title')&.inner_html
    rest  = node.css('.odice-card-line').map(&:inner_html)
    rows  = []
    rows << %(<div style="font-family:#{FONT};font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#{MUTED};margin:0 0 4px;">#{label}</div>) if label
    rows << %(<div style="font-family:#{FONT};font-size:16px;font-weight:700;line-height:1.4;color:#{NAVY};margin:0 0 6px;">#{head}</div>) if head
    rest.each { |line| rows << %(<div style="font-family:#{FONT};font-size:14px;line-height:1.5;color:#{TEXT};">#{line}</div>) }
    rows = [node.inner_html] if rows.empty?

    <<~HTML
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="display:table;width:100%;margin:4px 0 22px;border-collapse:collapse;">
        <tr><td style="padding:16px 18px;background:#{SOFT};border-left:4px solid #{CYAN};border-radius:6px;">#{rows.join}</td></tr>
      </table>
    HTML
  end

  def rating(node)
    cells = node.css('a').filter_map do |link|
      note = link['class'].to_s[%r{odice-note-(\d)}, 1].to_i
      next if !NOTES.key?(note)

      background, color = NOTES[note]
      label = link.inner_html.split(%r{<br\s*/?>}i).drop(1).join(' ').strip
      <<~HTML
        <td width="20%" align="center" valign="top" style="padding:3px;">
          <a href="#{ERB::Util.html_escape(link['href'])}" style="display:block;height:70px;padding:10px 0 0;background:#{background};border-radius:10px;color:#{color};text-decoration:none;font-family:#{FONT};overflow:hidden;">
            <span style="display:block;font-size:24px;font-weight:800;line-height:1.1;color:#{color};">#{note}</span>
            <span style="display:block;margin-top:4px;padding:0 2px;font-size:10px;line-height:1.2;color:#{color};word-break:break-word;">#{label}</span>
          </a>
        </td>
      HTML
    end

    <<~HTML
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="display:table;width:100%;table-layout:fixed;margin:6px 0 10px;border-collapse:separate;">
        <tr>#{cells.join}</tr>
      </table>
    HTML
  end

  def page(preheader:, title:, content:, signature:, footnote:)
    base = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}"
    logo = "#{base}/assets/images/odice-email-logo.png"
    name = ERB::Util.html_escape(Setting.get('product_name'))

    hidden = if preheader.present?
               %(<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">#{ERB::Util.html_escape(preheader)}#{'&#8199;&#65279;&#847; ' * 30}</div>)
             else
               ''
             end
    heading = if title.present?
                %(<h1 style="margin:0 0 18px;font-family:#{FONT};font-size:22px;line-height:1.3;font-weight:800;color:#{NAVY};">#{title}</h1>)
              else
                ''
              end
    sign = signature.present? ? %(<p style="#{P_STYLE}margin-top:22px;">#{signature}</p>) : ''
    note = if footnote.present?
             footnote
           else
             'Cet e-mail est envoyé automatiquement par le support du Groupe ODICE&nbsp;: merci de ne pas y répondre.'
           end

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light">
        <meta name="supported-color-schemes" content="light">
        <title>#{name}</title>
      </head>
      <body style="margin:0;padding:0;background:#{CANVAS};-webkit-text-size-adjust:100%;">
        #{hidden}
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#{CANVAS}" style="display:table;width:100%;background:#{CANVAS};border-collapse:collapse;margin:0;">
          <tr><td align="center" style="padding:28px 12px;">
            <table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="display:table;width:100%;max-width:600px;border-collapse:separate;margin:0;">
              <tr><td style="height:5px;line-height:5px;font-size:0;background:#{CYAN};border-radius:12px 12px 0 0;">&nbsp;</td></tr>
              <tr><td bgcolor="#ffffff" style="background:#ffffff;padding:26px 32px 8px;">
                <img src="#{logo}" width="150" alt="Groupe ODICE" style="display:block;border:0;outline:none;width:150px;height:auto;">
              </td></tr>
              <tr><td bgcolor="#ffffff" style="background:#ffffff;padding:18px 32px 30px;border-radius:0 0 12px 12px;">
                #{heading}
                #{content}
                #{sign}
              </td></tr>
              <tr><td align="center" style="padding:20px 24px 0;font-family:#{FONT};font-size:12px;line-height:1.6;color:#{MUTED};">
                #{note}<br>
                <a href="#{base}" style="color:#{MUTED};text-decoration:underline;">#{name}</a> · Groupe ODICE
              </td></tr>
            </table>
          </td></tr>
        </table>
      </body>
      </html>
    HTML
  end
end
