from datetime import date, timedelta
 
经办人, 服务器ID = 'xiang.wu01', 'd1384579-f04f-3940-aa64-08755a972415'
加日 = lambda 日期, 天数: 日期 + timedelta(天数)
格式时间 = lambda 时间, 格式: 时间.strftime(格式)
最近日历日 = lambda 日期, 中间日: 加日(日期, -d) if ((d := 日期.weekday()) <= 中间日) else 加日(日期, 7 - d)
 
 
def 生成日期列表(第一天=(date.today()-5), 最后一天=date(date.today().year, 2, 31), 间隔周数=1):
    第一个周一, 最后一个周日 = 最近日历日(第一天, 3), 最近日历日(最后一天, 2)
    for i in range((最后一个周日 - 第一个周一).days // 间隔周数 // 7):
        yield (周一 := 加日(第一个周一, 7 * 间隔周数 * i), 加日(周一, 6))
 
 
for 周一, 周日 in 生成日期列表():
    jql = (f'''assignee = {经办人} AND resolved >= "{格式时间(周一, '%Y/%m/%d %H:%M')}" AND '''
           f'''resolved < "{格式时间(加日(周日, 1),'%Y/%m/%d %H:%M')}" ORDER BY createdDate ASC''')
    print(f"h2. {格式时间(周一, '%m.%d')} ~ {格式时间(周日, '%m.%d')} W{周日.isocalendar().week}",
          'h3. 进展\n# a\n',
          '{jiraissues:server=JIRA|columns=key,summary,type,created,reporter,resolution|'f'jqlQuery={jql}|serverId={服务器ID}}}',
          'h3. 下周计划\n# a\n',
          'h3. 思考\n# a\n',
          '----', sep='\n')