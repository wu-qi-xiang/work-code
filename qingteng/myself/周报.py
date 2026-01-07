from datetime import date, timedelta
 
w = (date(2022, 3, 26), date(2022, 4, 2))
ww = [(w[0] + timedelta(i * 7), w[1] + timedelta(i * 7)) for i in range(2)]
fmt = lambda dt: dt.strftime('%Y/%m/%d %H:%M')
jql = '''assignee = xiang.wu01 AND ''' \
      '''resolved >= "{}" AND resolved < "{}" ORDER BY createdDate ASC'''
for w in ww:
    print('h2.', w[0].strftime('%m.%d'), '~', w[1].strftime('%m.%d'),
          'W{}'.format(w[1].isocalendar()[1]))
    print('h3. 进展')
    print('# a')
    print()
    print('''{{jiraissues:server=JIRA'''
         '''|columns=key,summary,type,created,reporter,resolution'''
         '''|jqlQuery={}'''
         '''|serverId=d1384579-f04f-3940-aa64-08755a972415}}'''.
         format(jql.format(fmt(w[0]), fmt(w[1] + timedelta(1)))))
    print('h3. 下周计划')
    print('# a')
    print()
    print('h3. 思考')
    print('# a')
    print()
    print('----')